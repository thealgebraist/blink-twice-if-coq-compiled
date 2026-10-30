### 1. Core Data Structures in Chromium Blink

In Chromium's Blink layout engine (specifically under LayoutNG / `blink/renderer/core/layout/list/`), list item and marker layout is governed by the following core representations:

*   **`EListStylePosition`**: The computed value enum representing CSS `list-style-position` (CSS Lists Level 3 §3.4):
    *   `EListStylePosition::kInside`: The `::marker` pseudo-element is placed as an inline child at the start of the list item's first principal line box.
    *   `EListStylePosition::kOutside`: The `::marker` box is placed outside the principal block box (in the inline-start margin/gutter area) and aligned with the first line box of the list item.
*   **`LayoutListItem` / `LayoutInlineListItem`**: The layout object representing an element with `display: list-item` (or `inline list-item`). It owns and manages the lifecycle of its associated marker layout object and delegates marker operations to `ListMarker`.
*   **`ListMarker`**: A helper class encapsulating marker-specific logic (text generation, suffix spacing, image vs. text marker categorization, and layout tree attachment). It distinguishes between:
    *   `LayoutListMarker` / `LayoutOutsideListMarker` (for `outside` positioning, creating an out-of-flow-like sibling or special child handled by `ListItemLayoutAlgorithm`).
    *   `LayoutInsideListMarker` (for `inside` positioning, participating directly in `InlineLayoutAlgorithm` as an atomic inline or inline text sequence).

---

### 2. Layout Positions and Geometry

Let $W_{\text{content}} \ge 0$ be the inline width of the principal content on the first line box, $W_{\text{marker}} \ge 0$ be the intrinsic inline width of the marker glyph/image, and $S_{\text{suffix}} \ge 0$ be the inline advance of the marker suffix/spacing. Define total marker advance $M = W_{\text{marker}} + S_{\text{suffix}}$.

1.  **`Inside` Positioning (`EListStylePosition::kInside`)**:
    *   **Placement**: The marker box is inserted at inline offset $0$ (relative to the line box inline-start edge).
    *   **Content Offset**: The principal line content begins immediately after the marker at inline offset $M$.
    *   **Line Box Width**: The total consumed inline advance of the first line box increases to $W_{\text{content}} + M$.

2.  **`Outside` Positioning (`EListStylePosition::kOutside`)**:
    *   **Placement**: The marker box is shifted into the inline-start gutter at negative inline offset $-M = -(W_{\text{marker}} + S_{\text{suffix}})$ relative to the list item's principal content box edge.
    *   **Content Offset**: The principal line content begins at inline offset $0$.
    *   **Line Box Width**: The marker does not participate in the inline formatting context's line width consumption; the line box content width remains $W_{\text{content}}$.

---

### 3. Mathematical Invariants

1.  **Inside Advance Conservation**:
    $$\forall W_{\text{content}}, W_{\text{marker}}, S_{\text{suffix}} \ge 0,\quad W_{\text{line}}(\text{Inside}) - W_{\text{content}} = W_{\text{marker}} + S_{\text{suffix}}$$
2.  **Outside Line Width Invariance**:
    $$\forall W_{\text{content}}, W_{\text{marker}}, S_{\text{suffix}} \ge 0,\quad W_{\text{line}}(\text{Outside}) = W_{\text{content}}$$
3.  **Outside Gutter Adjacency**:
    $$\text{Offset}_{\text{marker}}(\text{Outside}) + (W_{\text{marker}} + S_{\text{suffix}}) = \text{Offset}_{\text{content}}(\text{Outside}) = 0$$
4.  **Placement Determinism**:
    For any fixed tuple $(\text{Position}, W_{\text{content}}, W_{\text{marker}}, S_{\text{suffix}})$, the resulting layout geometry $(\text{Offset}_{\text{marker}}, \text{Offset}_{\text{content}}, W_{\text{line}})$ is unique.

---

### 4. Formalization in Rocq / Coq (`BlinkListMarkerPlacementSemantics.v`)

```coq
(** * BlinkListMarkerPlacementSemantics.v
    Formal audit of Chromium Blink List Marker Layout vs CSS Lists Level 3 §3. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** 1. Core Data Structures *)

(** Corresponds to blink::EListStylePosition *)
Inductive EListStylePosition : Type :=
  | Inside  : EListStylePosition
  | Outside : EListStylePosition.

(** Input metrics for the list marker and first line box content *)
Record ListItemMetrics : Type := mkMetrics {
  marker_width   : Z; (* Intrinsic inline size of marker glyph/image *)
  suffix_spacing : Z; (* Inline advance of suffix / margin spacing *)
  content_width  : Z; (* Principal inline content width on first line *)
}.

(** Well-formedness predicate: layout dimensions are non-negative *)
Definition wf_metrics (m : ListItemMetrics) : Prop :=
  0 <= marker_width m /\
  0 <= suffix_spacing m /\
  0 <= content_width m.

(** Total inline advance of the marker box *)
Definition total_marker_advance (m : ListItemMetrics) : Z :=
  marker_width m + suffix_spacing m.

(** Output geometry of the first line box and marker placement *)
Record LinePlacementResult : Type := mkPlacement {
  marker_inline_offset  : Z; (* Inline offset of marker relative to line start *)
  content_inline_offset : Z; (* Inline offset where principal content begins *)
  line_box_width        : Z; (* Total inline advance consumed in line box *)
}.

(** 2. Functional & Relational Layout Semantics *)

(** Functional specification of Blink's ListMarker + Inline/ListItem layout *)
Definition compute_marker_placement
  (pos : EListStylePosition) (m : ListItemMetrics) : LinePlacementResult :=
  let adv := total_marker_advance m in
  match pos with
  | Inside =>
      mkPlacement
        0                         (* Marker placed at start of line box *)
        adv                       (* Content shifted by marker advance *)
        (content_width m + adv)   (* Line box width increases by marker advance *)
  | Outside =>
      mkPlacement
        (- adv)                   (* Marker placed in gutter at negative offset *)
        0                         (* Content starts at line box origin *)
        (content_width m)         (* Line box width unchanged *)
  end.

(** Inductive relational semantics for verification *)
Inductive BlinkMarkerPlacementRel :
  EListStylePosition -> ListItemMetrics -> LinePlacementResult -> Prop :=
  | Place_Inside : forall m adv,
      adv = total_marker_advance m ->
      BlinkMarkerPlacementRel Inside m
        (mkPlacement 0 adv (content_width m + adv))
  | Place_Outside : forall m adv,
      adv = total_marker_advance m ->
      BlinkMarkerPlacementRel Outside m
        (mkPlacement (- adv) 0 (content_width m)).

(** 3. Theorems and Mathematical Invariants *)

(** Equivalence between functional and relational semantics *)
Theorem compute_placement_sound_complete :
  forall pos m res,
    compute_marker_placement pos m = res <->
    BlinkMarkerPlacementRel pos m res.
Proof.
  intros pos m res; split; intro H.
  - subst res. destruct pos; simpl.
    + apply Place_Inside; reflexivity.
    + apply Place_Outside; reflexivity.
  - destruct H; subst; reflexivity.
Qed.

(** Invariant 1: Inside marker increases line box advance by exact (w_marker + spacing) *)
Theorem inside_marker_increases_line_width :
  forall m res,
    BlinkMarkerPlacementRel Inside m res ->
    line_box_width res - content_width m = marker_width m + suffix_spacing m.
Proof.
  intros m res H.
  inversion H; subst.
  unfold total_marker_advance; simpl.
  lia.
Qed.

(** Invariant 2: Outside marker leaves line box content width unchanged *)
Theorem outside_marker_preserves_line_width :
  forall m res,
    BlinkMarkerPlacementRel Outside m res ->
    line_box_width res = content_width m.
Proof.
  intros m res H.
  inversion H; subst; simpl.
  reflexivity.
Qed.

(** Invariant 3: Outside marker is placed at exact negative offset -(w_marker + spacing) *)
Theorem outside_marker_gutter_offset :
  forall m res,
    BlinkMarkerPlacementRel Outside m res ->
    marker_inline_offset res = - (marker_width m + suffix_spacing m) /\
    marker_inline_offset res + total_marker_advance m = content_inline_offset res.
Proof.
  intros m res H.
  inversion H; subst.
  unfold total_marker_advance; simpl.
  split; lia.
Qed.

(** Invariant 4: Inside marker and content are contiguous and non-overlapping *)
Theorem inside_marker_contiguous_with_content :
  forall m res,
    BlinkMarkerPlacementRel Inside m res ->
    marker_inline_offset res + total_marker_advance m = content_inline_offset res.
Proof.
  intros m res H.
  inversion H; subst.
  unfold total_marker_advance; simpl.
  lia.
Qed.

(** Invariant 5: Non-negativity of line box width under well-formed metrics *)
Theorem line_box_width_nonneg :
  forall pos m res,
    wf_metrics m ->
    BlinkMarkerPlacementRel pos m res ->
    0 <= line_box_width res.
Proof.
  intros pos m res [Hm [Hs Hc]] Hrel.
  inversion Hrel; subst; unfold total_marker_advance; simpl; lia.
Qed.

(** Invariant 6: Determinism of marker placement *)
Theorem marker_placement_deterministic :
  forall pos m res1 res2,
    BlinkMarkerPlacementRel pos m res1 ->
    BlinkMarkerPlacementRel pos m res2 ->
    res1 = res2.
Proof.
  intros pos m res1 res2 H1 H2.
  apply compute_placement_sound_complete in H1.
  apply compute_placement_sound_complete in H2.
  congruence.
Qed.
```