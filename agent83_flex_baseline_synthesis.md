### 1. Core Data Structures in Blink Flex Baseline Calculations

In Chromium’s Blink engine (specifically within `third_party/blink/renderer/core/layout/flex/`), baseline alignment and synthesis rely on a precise hierarchy of layout structures:

*   **`NGFlexItem` / `FlexItem`**: The foundational representation of a flex child during layout. For baseline alignment, its critical fields are:
    *   `cross_axis_size`: The computed border-box size of the item in the flex line's cross axis (`LayoutUnit`).
    *   `margins`: Stored as a `LogicalBoxStrut` (or `PhysicalBoxStrut` converted to logical coordinates), representing `inline_start`, `inline_end`, `block_start`, and `block_end` margins.
    *   `baseline_group`: Determined by the item's `align-self` property (`kFirstBaseline` vs. `kLastBaseline`) and its writing mode relative to the flex container's cross axis.
    *   `layout_result`: A pointer to the `NGLayoutResult` produced by laying out the item, which exposes `FirstBaseline()` and `LastBaseline()` as `std::optional<LayoutUnit>`.
*   **`BaselineGroup` (`FontBaseline` & Alignment Context)**: Blink partitions baseline-aligned items on a single flex line into two distinct groups: *Major* (typically `first baseline`) and *Minor* (typically `last baseline`), depending on the flex direction and writing mode orthogonality. Each group tracks an accumulator state:
    *   `max_ascent`: The maximum distance from the margin-box cross-start (or cross-end for minor groups) to the item's baseline across all items in the group.
    *   `max_descent`: The maximum distance from the item's baseline to the margin-box cross-end (or cross-start).
*   **`FontBaseline`**: An enumeration (`kAlphabeticBaseline`, `kIdeographicBaseline`) dictated by the `writing-mode` and `text-orientation` of the flex container. Horizontal writing modes default to `kAlphabeticBaseline`, while vertical modes typically use `kIdeographicBaseline` (central) unless overridden.
*   **`LogicalBoxStrut`**: A 4-tuple of `LayoutUnit` values (`inline_start`, `inline_end`, `block_start`, `block_end`) used to represent borders, padding, and margins in the flow-relative coordinate space of the flex container or item.

---

### 2. First vs. Last Baseline Synthesis

Per **CSS Flexbox 1 §8.5** and **CSS Box Alignment 3 §9.2**, if a flex item participates in baseline alignment (`align-self: baseline` or `last baseline`) and its inline axis is parallel to the flex container's main axis, Blink extracts or synthesizes its baseline offset via `NGFlexLayoutAlgorithm::BaselineForItem` and `NGBoxFragment::Baseline`:

1.  **Natural Baseline Extraction**:
    *   Blink queries the item's `NGPhysicalBoxFragment` (converted to logical `NGBoxFragment`).
    *   For **First Baseline**: It traverses in-flow children in tree order to find the first child that exports a valid first baseline (e.g., a line box with text, or a nested block/flex/grid container with its own baseline). If found, the offset is translated into the item's border-box coordinate space (measured from the `block_start` border edge).
    *   For **Last Baseline**: It traverses in-flow children in reverse tree order to find the last child exporting a valid last baseline.
2.  **Baseline Synthesis (Fallback)**:
    *   If the item has no in-flow children, establishes a scroll container (`overflow` other than `visible` in certain contexts, though CSS Box Alignment 3 updates scroll container baseline rules to clamp or use inner content), or its children produce no baseline (e.g., an empty `<div>` or an `<img>`):
    *   **First Baseline Synthesis**: Blink synthesizes the baseline at the item's under/block-end margin edge or border-box edge depending on the box type. Specifically, for an atomic inline or flex item without an internal baseline, the synthesized baseline falls back to the **border-box `block_end` edge** (i.e., `offset = border_box_cross_size`), which, when combined with `margin.block_end` during ascent/descent calculation, aligns the margin-box bottom with the baseline, or in strict CSS Box Alignment 3 §9.2 terms for flex items, synthesizes from the border box's under edge (`block_end` border edge).
    *   **Last Baseline Synthesis**: Similarly, if no natural last baseline exists, it is synthesized at the border-box `block_end` edge (or `block_start` edge if flipped by `flex-wrap: wrap-reverse` / orthogonal writing modes).

---

### 3. Multi-Item Baseline Grouping (`max_ascent` & `max_descent`)

Within `FlexLine`, Blink iterates over all `FlexItem` instances on the current line before finalizing the line's cross size (`cross_axis_extent`):

For each item $i$ with `align-self` resolving to baseline alignment:
1.  Compute the item's border-box baseline offset $B_i \in [0, S_i]$, where $S_i$ is the item's border-box cross size (`cross_axis_size`).
2.  Calculate the **Margin-Box Ascent** ($A_i$) and **Margin-Box Descent** ($D_i$):
    *   For **First Baseline** (Major Group):
        $$A_i = \text{margin\_start}_i + B_i$$
        $$D_i = (S_i - B_i) + \text{margin\_end}_i$$
    *   For **Last Baseline** (Minor Group), Blink measures the baseline relative to the cross-end edge (or inverts the ascent/descent orientation):
        $$A_i^{\text{last}} = \text{margin\_start}_i + B_i^{\text{last}}$$
        $$D_i^{\text{last}} = (S_i - B_i^{\text{last}}) + \text{margin\_end}_i$$
3.  Update the group accumulators across all items $i$ in the baseline group $G$:
    $$\text{max\_ascent}_G = \max_{i \in G} (A_i)$$
    $$\text{max\_descent}_G = \max_{i \in G} (D_i)$$
4.  **Cross-Axis Positioning**: Once `max_ascent` is known for the group, any item $i \in G$ is positioned along the cross axis of the flex line such that its margin-box cross-start edge is placed at offset:
    $$\text{offset}_i = \text{max\_ascent}_G - A_i$$
    Consequently, its actual border-box cross-start edge is placed at:
    $$\text{border\_box\_offset}_i = \text{offset}_i + \text{margin\_start}_i = \text{max\_ascent}_G - B_i$$
    This guarantees that for all $i, j \in G$, their baselines coincide at exact coordinate $\text{max\_ascent}_G$ relative to the group's alignment origin.

---

### 4. Mathematical Invariants

1.  **Synthesized Baseline Boundedness**:
    For any flex item $i$ with non-negative border-box cross size $S_i \ge 0$, the synthesized (or clamped natural) baseline offset $B_i$ relative to its border-box cross-start edge satisfies:
    $$0 \le B_i \le S_i$$
2.  **Margin-Box Size Partitioning**:
    For every baseline-aligned item $i$, the sum of its ascent $A_i$ and descent $D_i$ equals its total outer (margin-box) cross size $M_i$:
    $$A_i + D_i = (\text{margin\_start}_i + B_i) + (S_i - B_i + \text{margin\_end}_i) = \text{margin\_start}_i + S_i + \text{margin\_end}_i = M_i$$
3.  **Flex Line Cross Size Lower Bound**:
    Let $L_{\text{cross}}$ be the computed cross size of the flex line (`cross_axis_extent`). Per CSS Flexbox 1 §9.4 Step 9, $L_{\text{cross}}$ is the maximum of the outer cross sizes of non-baseline-aligned items and the sum of the maximum ascent and maximum descent of each baseline group:
    $$L_{\text{cross}} \ge \text{max\_ascent}_G + \text{max\_descent}_G$$
    Furthermore, for every individual item $i \in G$:
    $$\text{max\_ascent}_G + \text{max\_descent}_G \ge A_i + D_i = M_i$$
    Therefore, no baseline-aligned item's margin box overflows the flex line cross size.

---

### 5. Rocq / Coq Formalization (`BlinkFlexBaselineSynthesisSemantics.v`)

The following self-contained Rocq (Coq) formalization encodes the data structures, synthesis logic, baseline group accumulation, and proves the core mathematical invariants.

```coq
(** * BlinkFlexBaselineSynthesisSemantics.v
    Formalization of Chromium Blink Flexbox Baseline Alignment & Synthesis
    against CSS Flexible Box Layout Module Level 1 (§8.5) and
    CSS Box Alignment Module Level 3 (§9). *)

From Coq Require Import Arith Psatz List Bool.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Core Data Structures *)

Inductive FontBaseline : Type :=
  | AlphabeticBaseline
  | IdeographicBaseline.

Inductive BaselineGroupKind : Type :=
  | FirstBaselineGroup
  | LastBaselineGroup.

Inductive AlignSelf : Type :=
  | AlignFlexStart
  | AlignFlexEnd
  | AlignCenter
  | AlignStretch
  | AlignBaseline (group : BaselineGroupKind).

Record LogicalBoxStrut : Type := mkStrut {
  inline_start : nat;
  inline_end   : nat;
  block_start  : nat;
  block_end    : nat
}.

Record FlexItem : Type := mkFlexItem {
  cross_axis_size   : nat;
  margins           : LogicalBoxStrut;
  padding_border    : LogicalBoxStrut;
  align_self        : AlignSelf;
  natural_first_bl  : option nat;
  natural_last_bl   : option nat
}.

Record BaselineGroupState : Type := mkBaselineGroupState {
  max_ascent  : nat;
  max_descent : nat
}.

(** ** 2. First vs. Last Baseline Synthesis *)

(** Clamp a natural baseline into the border-box cross size [0, cross_axis_size]
    to model well-formed layout fragment baselines, or synthesize at the
    border-box edge if absent. *)
Definition synthesize_baseline (item : FlexItem) (kind : BaselineGroupKind) : nat :=
  let size := cross_axis_size item in
  match kind with
  | FirstBaselineGroup =>
      match natural_first_bl item with
      | Some b => Nat.min b size
      | None   => size (* Fallback to border-box block-end edge *)
      end
  | LastBaselineGroup =>
      match natural_last_bl item with
      | Some b => Nat.min b size
      | None   => size (* Fallback to border-box block-end edge *)
      end
  end.

(** Ascent and Descent calculation including block/cross margins. *)
Definition item_ascent (item : FlexItem) (kind : BaselineGroupKind) : nat :=
  block_start (margins item) + synthesize_baseline item kind.

Definition item_descent (item : FlexItem) (kind : BaselineGroupKind) : nat :=
  (cross_axis_size item - synthesize_baseline item kind) + block_end (margins item).

Definition item_outer_cross_size (item : FlexItem) : nat :=
  block_start (margins item) + cross_axis_size item + block_end (margins item).

(** ** 3. Multi-Item Baseline Grouping *)

Definition empty_group_state : BaselineGroupState :=
  mkBaselineGroupState 0 0.

Definition update_group_state (st : BaselineGroupState) (item : FlexItem) (kind : BaselineGroupKind) : BaselineGroupState :=
  mkBaselineGroupState
    (Nat.max (max_ascent st) (item_ascent item kind))
    (Nat.max (max_descent st) (item_descent item kind)).

Definition eqb_group_kind (k1 k2 : BaselineGroupKind) : bool :=
  match k1, k2 with
  | FirstBaselineGroup, FirstBaselineGroup => true
  | LastBaselineGroup, LastBaselineGroup   => true
  | _, _ => false
  end.

Fixpoint compute_baseline_group (items : list FlexItem) (kind : BaselineGroupKind) : BaselineGroupState :=
  match items with
  | [] => empty_group_state
  | item :: rest =>
      let st_rest := compute_baseline_group rest kind in
      match align_self item with
      | AlignBaseline k =>
          if eqb_group_kind k kind then update_group_state st_rest item kind
          else st_rest
      | _ => st_rest
      end
  end.

Definition group_cross_size (st : BaselineGroupState) : nat :=
  max_ascent st + max_descent st.

Fixpoint max_non_baseline_cross_size (items : list FlexItem) : nat :=
  match items with
  | [] => 0
  | item :: rest =>
      let rest_max := max_non_baseline_cross_size rest in
      match align_self item with
      | AlignBaseline _ => rest_max
      | _ => Nat.max (item_outer_cross_size item) rest_max
      end
  end.

(** Flex line cross size per CSS Flexbox 1 §9.4 *)
Definition compute_line_cross_size (items : list FlexItem) : nat :=
  let first_grp := compute_baseline_group items FirstBaselineGroup in
  let last_grp  := compute_baseline_group items LastBaselineGroup in
  let non_bl    := max_non_baseline_cross_size items in
  Nat.max (group_cross_size first_grp)
          (Nat.max (group_cross_size last_grp) non_bl).

(** ** 4. Mathematical Invariants & Proofs *)

(** Invariant 1: Synthesized baseline is bounded within the item's border box. *)
Theorem synthesized_baseline_bounded :
  forall (item : FlexItem) (kind : BaselineGroupKind),
    0 <= synthesize_baseline item kind <= cross_axis_size item.
Proof.
  intros item kind.
  unfold synthesize_baseline.
  destruct kind; [destruct (natural_first_bl item) | destruct (natural_last_bl item)];
  lia.
Qed.

(** Invariant 2: Ascent + Descent exactly equals the item's outer (margin-box) cross size. *)
Theorem ascent_plus_descent_eq_outer_size :
  forall (item