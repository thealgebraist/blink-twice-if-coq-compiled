### 1. Representation of Subgrid Axis Inheritance in Chromium Blink

In Chromium’s LayoutNG Grid implementation (`third_party/blink/renderer/core/layout/grid/`), CSS Grid Layout Module Level 2 §2 (Subgrids) is realized by dissociating track collection ownership from item placement resolution across nested grid boundaries.

#### `GridSubtree` and `GridSizingTree`
Blink flattens the nested grid hierarchy into a contiguous pre-order array of `GridTreeNode` instances inside `GridSizingTree`. `GridSubtree` acts as a lightweight cursor over this vector, computing subtree spans via index offsets:
* **Track Adoption**: A subgridded axis does not allocate an independent `GridTrackSizingAlgorithm` collection. During `GridLayoutAlgorithm::BuildGridSizingSubtree`, if `GridNode::HasSubgriddedAxis(direction)` is true, the subgrid constructs a `GridLayoutSubtree` that forwards a view of the parent's `GridLayoutTrackCollection` (specifically, a sub-range slice of `GridSizingTrackCollection` or `GridRangeVector`) down to the subgrid's layout pass.
* **Axis Independence**: `GridTrackCollectionBase` and `GridLineResolver` operate per-axis (`kForColumns` vs `kForRows`). A subgrid may adopt parent tracks in one axis while establishing an independent `GridSizingTrackCollection` in the orthogonal axis.

#### `GridLineResolver`
`GridLineResolver` manages line-to-track resolution and named line lookup (`grid-template-columns: subgrid [line-name]`).
* When constructing a `GridLineResolver` for a subgrid (`GridLineResolver(const ComputedStyle&, const GridLineResolver& parent_line_resolver, GridArea subgrid_area, ...)`), the resolver stores `subgrid_span_size_` (computed as $\text{parent\_end\_line} - \text{parent\_start\_line}$).
* **Explicit Grid Override**: For a subgridded axis, `ExplicitGridTrackCount()` ignores `grid-template-rows`/`columns` track listings and forcibly returns `subgrid_span_size_`.
* **Implicit Grid Suppression**: Per CSS Grid 2 §2.1 ("Subgrids do not have implicit tracks in the subgridded dimension(s)"), `GridLineResolver` disables implicit track expansion along the subgridded axis. Named lines from the parent's `GridNamedLineCollection` falling within `[subgrid_area.StartLine(), subgrid_area.EndLine()]` are re-indexed relative to 0 (the subgrid's local origin) and merged with the subgrid's local `[line-name]` declarations.

---

### 2. Line Index Translation Mechanics

In Blink, grid lines are normalized to **0-based untranslated indices** where line $0$ is the start edge of the explicit grid. However, once a subgrid resolves its own placement within its parent, its placement is recorded as a `GridSpan` $[S_{\text{parent}}, E_{\text{parent}})$ in the parent's **translated** coordinate space (where $0$ is the first track of the parent's full—implicit + explicit—grid, and $0 \le S_{\text{parent}} < E_{\text{parent}}$).

#### Step-by-Step Translation Pipeline:
1. **Local Resolution**: A subgrid child specifies placement (e.g., `grid-column: 2 / -1` or `span 3`). The subgrid's `GridLineResolver` resolves these against an effective explicit track count of $N_{\text{sub}} = E_{\text{parent}} - S_{\text{parent}}$.
2. **Clamping (No Implicit Tracks)**: In a standard grid, a resolved span $[s_{\text{local}}, e_{\text{local}})$ outside $[0, N_{\text{explicit}}]$ triggers implicit track creation and shifts the coordinate origin via `explicit_grid_offset`. In a subgridded axis, `GridItemData` clamps $[s_{\text{local}}, e_{\text{local}})$ directly to $[0, N_{\text{sub}}]$ (represented via `GridSpan::TranslatedDefiniteGridSpan`), ensuring $0 \le s_{\text{local}} < e_{\text{local}} \le N_{\text{sub}}$.
3. **Parent Projection (`Translate` / Offset Accumulation)**: When subgrid items are lifted into the parent's `GridItems` collection for joint track sizing (CSS Grid 2 §2.3), their local `GridSpan` $[s_{\text{local}}, e_{\text{local}})$ is translated by `subgrid_area.StartLine()` ($S_{\text{parent}}$):
   $$s_{\text{in\_parent}} = S_{\text{parent}} + s_{\text{local}}, \quad e_{\text{in\_parent}} = S_{\text{parent}} + e_{\text{local}}$$
   For deeply nested subgrids ($k$ levels), this translation is a composition of offsets $\sum_{i=1}^{k} S_{\text{parent}}^{(i)}$.

---

### 3. Core Invariants

1. **Subgrid Track Count Equivalence (CSS Grid 2 §2.1)**:
   The number of tracks available in a subgridded axis is strictly equal to the number of parent tracks spanned by the subgrid container:
   $$\text{TrackCount}(\text{Subgrid}) = \text{SpanSize}(\text{SubgridInParent}) = E_{\text{parent}} - S_{\text{parent}} \ge 1$$
2. **Strict Sub-Range Containment (Clamping Invariant, CSS Grid 2 §2.1 & §8.3)**:
   No child of a subgrid can induce implicit tracks in the subgridded axis. Every subgrid item's local span $[s_{\text{local}}, e_{\text{local}})$, once clamped and projected into the parent's coordinate space, is a valid, non-empty sub-interval of the subgrid's own parent span $[S_{\text{parent}}, E_{\text{parent}})$:
   $$S_{\text{parent}} \le s_{\text{in\_parent}} < e_{\text{in\_parent}} \le E_{\text{parent}}$$
3. **Transitive Composition across `GridSubtree`**:
   If Subgrid $B$ is a child of Subgrid $A$, and Subgrid $A$ is a child of Root Grid $R$, projecting an item from $B \to A \to R$ is identical to projecting directly via the composed span of $B$ in $R$, preserving interval containment at every level of the `GridSizingTree`.

---

### 4. Formal Verification in Rocq/Coq (`BlinkGridSubgridAxisSemantics.v`)

The following self-contained Coq development models Blink's `GridSpan`, `GridLineResolver` clamping for subgridded axes, and `GridSubtree` offset translation, proving the core invariants.

```coq
(** * BlinkGridSubgridAxisSemantics.v
    Formal audit of Chromium Blink CSS Grid 2 Subgrid Axis Inheritance (§2).
    Models GridSpan, GridLineResolver subgrid clamping, and GridSubtree translation. *)

From Coq Require Import Arith PeanoNat Lia Bool.

Module BlinkGridSubgridAxisSemantics.

(** ** 1. Grid Coordinate and Span Representation
    Corresponds to blink::GridSpan (0-based translated definite grid spans). *)

Record GridSpan : Type := mkGridSpan {
  start_line : nat;
  end_line   : nat
}.

(** A well-formed definite GridSpan in Blink satisfies start_line < end_line.
    (CSS Grid guarantees a minimum span size of 1 track). *)
Definition wf_span (s : GridSpan) : Prop :=
  start_line s < end_line s.

(** Number of tracks spanned: blink::GridSpan::IntegerSpan() *)
Definition span_size (s : GridSpan) : nat :=
  end_line s - start_line s.

(** Containment of a span within a parent track count or another span. *)
Definition span_within_bounds (s : GridSpan) (track_count : nat) : Prop :=
  start_line s < end_line s /\ end_line s <= track_count.

Definition subspan_of (child parent : GridSpan) : Prop :=
  start_line parent <= start_line child /\
  start_line child < end_line child /\
  end_line child <= end_line parent.

(** ** 2. Subgrid Axis Inheritance & Line Resolution
    Corresponds to blink::GridLineResolver in a subgridded axis. *)

Record SubgridAxisContext : Type := mkSubgridAxisContext {
  parent_track_count : nat;
  subgrid_span       : GridSpan (* The subgrid's resolved span inside its parent *)
}.

Definition wf_subgrid_context (ctx : SubgridAxisContext) : Prop :=
  span_within_bounds (subgrid_span ctx) (parent_track_count ctx).

(** CSS Grid 2 §2.1: Subgrid explicit track count equals spanned parent tracks. *)
Definition subgrid_explicit_track_count (ctx : SubgridAxisContext) : nat :=
  span_size (subgrid_span ctx).

(** Clamping logic for subgrid items (CSS Grid 2 §2.1 / §8.3):
    Subgrids have no implicit grid in the subgridded axis. Any raw resolved lines
    [raw_start, raw_end] (after negative line resolution and span expansion)
    are clamped to [0, N_sub], preserving at least a 1-track span. *)
Definition clamp_to_subgrid (N_sub : nat) (raw_start raw_end : nat) : GridSpan :=
  let s := Nat.min raw_start (N_sub - 1) in
  let e := Nat.max (s + 1) (Nat.min raw_end N_sub) in
  mkGridSpan s e.

(** Translation of a local subgrid item span into the parent grid's coordinate space.
    Corresponds to blink::GridSpan::Translate(subgrid_span.StartLine()). *)
Definition translate_to_parent (ctx : SubgridAxisContext) (local_span : GridSpan) : GridSpan :=
  let offset := start_line (subgrid_span ctx) in
  mkGridSpan (offset + start_line local_span) (offset + end_line local_span).

(** Full resolution pipeline for a subgrid child item in a subgridded axis. *)
Definition resolve_subgrid_item_in_parent
  (ctx : SubgridAxisContext) (raw_start raw_end : nat) : GridSpan :=
  let N_sub := subgrid_explicit_track_count ctx in
  let local := clamp_to_subgrid N_sub raw_start raw_end in
  translate_to_parent ctx local.

(** ** 3. Theorems & Invariant Proofs *)

(** Invariant 1: A well-formed subgrid context always yields at least 1 track,
    and its track count is bounded by the parent's track count. *)
Theorem subgrid_track_count_valid :
  forall (ctx : SubgridAxisContext),
    wf_subgrid_context ctx ->
    1 <= subgrid_explicit_track_count ctx /\
    subgrid_explicit_track_count ctx <= parent_track_count ctx.
Proof.
  intros ctx [Hlt Hle].
  unfold subgrid_explicit_track_count, span_size.
  lia.
Qed.

(** Invariant 2: Clamping any raw placement to a valid subgrid track count N_sub >= 1
    produces a well-formed local span strictly within [0, N_sub]. *)
Theorem clamp_to_subgrid_within_bounds :
  forall (N_sub raw_start raw_end : nat),
    1 <= N_sub ->
    span_within_bounds (clamp_to_subgrid N_sub raw_start raw_end) N_sub.
Proof.
  intros N_sub raw_start raw_end HN.
  unfold span_within_bounds, clamp_to_subgrid; simpl.
  split; lia.
Qed.

(** Invariant 3: Translating a bounded local span into the parent coordinate space
    preserves exact track span size. *)
Theorem translate_preserves_span_size :
  forall (ctx : SubgridAxisContext) (local_span : GridSpan),
    span_size (translate_to_parent ctx local_span) = span_size local_span.
Proof.
  intros ctx local_span.
  unfold translate_to_parent, span_size; simpl.
  lia.
Qed.

(** Invariant 4 (Primary Audit Theorem):
    Every subgrid child item resolved and translated into the parent grid
    is a well-formed subspan of the subgrid's own parent span, and never
    triggers implicit tracks in the parent grid (remains within parent_track_count). *)
Theorem subgrid_item_contained_in_parent_span :
  forall (ctx : SubgridAxisContext) (raw_start raw_end : nat),
    wf_subgrid_context ctx ->
    let parent_resolved := resolve_subgrid_item_in_parent ctx raw_start raw_end in
    subspan_of parent_resolved (subgrid_span ctx) /\
    span_within_bounds parent_resolved (parent_track_count ctx).
Proof.
  intros ctx raw_start raw_end Hwf parent_resolved.
  pose proof (subgrid_track_count_valid ctx Hwf) as [HN1 HN2].
  pose proof (clamp_to_subgrid_within_bounds
                (subgrid_explicit_track_count ctx) raw_start raw_end HN1) as [Hcl_lt Hcl_le].
  unfold wf_subgrid_context, span_within_bounds in Hwf.
  destruct Hwf as [Hsub_lt Hsub_le].
  unfold parent_resolved, resolve_subgrid_item_in_parent, translate_to_parent,
         subgrid_explicit_track_count, span_size, subspan_of, span_within_bounds in *;
  simpl in *.
  split; [split; [| split] | split]; lia.
Qed.

(** Invariant 5: Multi-level GridSubtree Transitivity.
    Translating a grandchild item from Subgrid2 -> Subgrid1 -> RootGrid is associative
    with composing the subgrid contexts directly. *)
Theorem grid_subtree_translation_associative :
  forall (ctx1 : SubgridAxisContext) (sub2_local_span item_local_span : GridSpan),
    wf_subgrid_context ctx1 ->
    span_within_bounds sub2_local_span (subgrid_explicit_track_count ctx1) ->
    span_within_bounds item_local_span (span_size sub2_local_span) ->
    let sub2_in_root := translate_to_parent ctx1 sub2_local_span in
    let ctx2_in_sub1 := mkSubgridAxisContext (subgrid_explicit_track_count ctx1) sub2_local_span in
    let ctx2_in_root := mkSubgridAxisContext (parent_track_count ctx1) sub2_in_root in
    translate_to_parent ctx1 (translate_to_parent ctx2_in_sub1 item_local_span) =
    translate_to_parent ctx2_in_