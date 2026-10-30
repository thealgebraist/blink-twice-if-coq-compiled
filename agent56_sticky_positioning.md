### 1. Core Data Structures in Blink Sticky Positioning

In Chromium's Blink engine (located primarily in `third_party/blink/renderer/core/layout/` and `core/page/scrolling/`), sticky positioning is resolved across the layout and compositing phases using three conceptual data structures (manifested in C++ via `StickyPositionScrollingConstraints` and layout geometry structs):

*   **`StickyPositionOffsetData` (`StickyPositionScrollingConstraints`)**: 
    Stores the precomputed geometric invariants required by both the main thread and the compositor thread (`cc::StickyPositionNodeData`) to update sticky offsets dynamically during scrolling without triggering a full layout pass.
    *   `is_anchored_top`, `is_anchored_bottom`, `is_anchored_left`, `is_anchored_right`: Boolean flags indicating active CSS inset properties (`top`, `bottom`, `left`, `right`).
    *   `top_offset`, `bottom_offset`, `left_offset`, `right_offset`: The computed `LayoutUnit` (fixed-point) values of the respective CSS insets.
    *   `scroll_container_relative_sticky_box_rect`: The static layout rectangle of the sticky element's border box in the coordinate space of the nearest scroll container.
    *   `scroll_container_relative_containing_block_rect`: The content box rectangle of the sticky element's containing block (shifted by its insets) in the coordinate space of the scroll container.
    *   `nearest_sticky_layer_shifting_sticky_box` & `nearest_sticky_layer_shifting_containing_block`: References to ancestor sticky elements that shift this element or its containing block, ensuring cumulative offsets are accounted for.

*   **`ScrollerOffsets`**:
    Represents the dynamic state of the nearest scroll container (`LayoutBox` with scrollbars / `PaintLayerScrollableArea`).
    *   `scroll_offset`: The current 2D scroll position $(S_x, S_y)$ relative to the scroll origin.
    *   `scrollport_rect`: The visible viewport area of the scroll container (excluding scrollbars, clipped by padding box), positioned at `scroll_offset` with dimensions $(W_{vp}, H_{vp})$.

*   **`ContainingBlockConstraints`**:
    Defines the bounding region within which the sticky element is permitted to float. Per CSS Position Level 3 §6, a sticky box cannot escape its containing block.
    *   `cb_content_rect`: The layout rectangle of the containing block's content area.
    *   `available_space`: The maximum travel distance of the sticky box along a given axis, computed as the containing block extent minus the sticky box's margin-box extent: $\max(0, L_{cb} - L_{box})$.

---

### 2. Sticky 1D Offset Computation

To isolate the core mechanics for a top-anchored (or inline-start-anchored) sticky element, Blink reduces the 2D layout constraints into two independent 1D axial computations. 

Let the 1D coordinate space be relative to the scroll container's origin, where:
*   `scroll_offset` ($S$): The current scroll position along the axis, plus the specified CSS sticky inset (e.g., $S_{raw} + \text{inset}_{top}$).
*   `static_position` ($P_{static}$): The initial, unshifted offset of the sticky box within its containing block along the scroll axis.
*   `cb_extent` ($L_{cb}$): The length of the containing block along the axis (measured from $P_{static}$ to the trailing edge of the containing block).
*   `box_extent` ($L_{box}$): The length of the sticky element's margin box along the axis.

When scrolling pushes the viewport past the element's static position ($S > P_{static}$), the sticky element must shift positively by $S - P_{static}$ to remain fixed relative to the scrollport. However, it cannot shift further than the remaining space inside its containing block ($L_{cb} - L_{box}$). 

Thus, the 1D sticky offset $\Delta$ is governed by the clamping equation:

$$\Delta = \text{clamp}(0, \, S - P_{static}, \, \max(0, L_{cb} - L_{box}))$$

Where $\text{clamp}(min, val, max) = \max(min, \min(val, max))$. Note that if $L_{cb} < L_{box}$ (the sticky element is larger than its containing block), the upper bound collapses to $0$, preventing negative offsets when clamping.

---

### 3. Boundary Constraints

The interaction between the scrollport and the containing block establishes two hard boundary constraints that govern the lifecycle of a sticky element during a scroll gesture:

1.  **Viewport Scroll Boundaries (The Sticky View Rectangle)**:
    The scroll container's viewport is shrunk by the element's CSS `top`, `right`, `bottom`, and `left` properties to form the *sticky view rectangle*. The element remains in its normal flow position until the scrolling action causes the edge of the sticky view rectangle to intersect the element's static border box. This establishes the lower bound of the offset ($\Delta \ge 0$ for top/left anchoring), ensuring the element never moves *backward* against the scroll direction past its static layout origin.

2.  **Containing Block Rect (The Containment Boundary)**:
    As scrolling continues, the element translates along with the sticky view rectangle. However, its translated border box (specifically, its margin box in CSS specs, though Blink historically resolved edge cases using border-box/padding-box intersections) must remain strictly inside the content box of its containing block. Once $\Delta = L_{cb} - L_{box}$, the trailing edge of the sticky box hits the trailing edge of the containing block. At this threshold, the element stops floating and scrolls out of view alongside its containing block.

---

### 4. Mathematical Invariants

For any valid 1D top/left-anchored sticky computation in Blink, the following invariants hold over $\mathbb{Z}$ (modeling Blink's `LayoutUnit` fixed-point arithmetic):

1.  **Non-Negativity (`offset_non_negative`)**:
    $$\forall S, P_{static}, L_{cb}, L_{box} \in \mathbb{Z}, \quad \Delta \ge 0$$
    A top- or left-anchored sticky element can only be pushed forward (positively) along the scroll axis relative to its static position.

2.  **Containment Bound (`offset_bounded_by_containment`)**:
    $$\forall S, P_{static}, L_{cb}, L_{box} \in \mathbb{Z}, \quad L_{cb} \ge L_{box} \implies \Delta \le L_{cb} - L_{box}$$
    Assuming the containing block is at least as large as the sticky box, the computed offset never exceeds the available travel distance within the containing block, guaranteeing that $P_{static} + \Delta + L_{box} \le P_{static} + L_{cb}$.

3.  **Determinism (`offset_deterministic`)**:
    $$\forall c \in \text{Constraints}, s \in \text{Scroller}, \quad \text{compute}(c, s) = \Delta_1 \land \text{compute}(c, s) = \Delta_2 \implies \Delta_1 = \Delta_2$$
    Because Blink's sticky offset resolution is a pure function of layout geometry and scroll offset (free of hysteresis or frame-rate dependent state), identical scroll offsets and layout constraints strictly yield identical sticky translations on both the main and compositor threads.

---

### 5. Rocq / Coq Formalization (`BlinkStickyPositionSemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization of the 1D sticky positioning semantics, including the core data structures, clamping arithmetic, inductive relational semantics, and machine-checked proofs of the mathematical invariants using `Lia`.

```coq
(** * BlinkStickyPositionSemantics.v
    Formalization of Chromium Blink Sticky Positioning vs CSS Position Level 3 §6.
    Agent 56 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Represents the static layout geometry of the sticky box and its containing block. *)
Inductive ContainingBlockConstraints : Type :=
  | mkConstraints (static_position : Z) (cb_extent : Z) (box_extent : Z).

(** Represents the dynamic scroll state of the nearest scroll container. *)
Inductive ScrollerOffsets : Type :=
  | mkScroller (scroll_offset : Z).

(** Represents the complete input state for Blink's 1D sticky offset calculation. *)
Inductive StickyPositionOffsetData : Type :=
  | mkStickyData (constraints : ContainingBlockConstraints) (scroller : ScrollerOffsets).

(** Projectors for readability *)
Definition get_static_pos (c : ContainingBlockConstraints) : Z :=
  match c with mkConstraints p _ _ => p end.

Definition get_cb_extent (c : ContainingBlockConstraints) : Z :=
  match c with mkConstraints _ cb _ => cb end.

Definition get_box_extent (c : ContainingBlockConstraints) : Z :=
  match c with mkConstraints _ _ b => b end.

Definition get_scroll_offset (s : ScrollerOffsets) : Z :=
  match s with mkScroller so => so end.

(** ** 2. Sticky 1D Offset Computation *)

(** Available containment space is non-negative: max(0, cb_extent - box_extent).
    This prevents inverted bounds in clamp when the sticky box overflows its CB. *)
Definition available_space (cb_extent box_extent : Z) : Z :=
  Z.max 0 (cb_extent - box_extent).

(** Standard clamping operation: clamp(min_val, val, max_val).
    Defined as Z.max min_val (Z.min val max_val) to guarantee min_val <= result
    even if max_val < min_val, though available_space prevents bound inversion. *)
Definition clamp (min_val val max_val : Z) : Z :=
  Z.max min_val (Z.min val max_val).

(** Functional specification of Blink's 1D sticky offset computation:
    offset = clamp(0, scroll_offset - static_position, max(0, cb_extent - box_extent)) *)
Definition compute_sticky_offset_1d (data : StickyPositionOffsetData) : Z :=
  match data with
  | mkStickyData (mkConstraints static_pos cb_ext box_ext) (mkScroller scroll_off) =>
      let raw_offset := scroll_off - static_pos in
      let max_offset := available_space cb_ext box_ext in
      clamp 0 raw_offset max_offset
  end.

(** Relational (Inductive) semantics of Blink's sticky offset resolution. *)
Inductive StickyOffsetStep : StickyPositionOffsetData -> Z -> Prop :=
  | Step_Sticky1D : forall static_pos cb_ext box_ext scroll_off raw max_off res,
      raw = scroll_off - static_pos ->
      max_off = available_space cb_ext box_ext ->
      res = clamp 0 raw max_off ->
      StickyOffsetStep
        (mkStickyData (mkConstraints static_pos cb_ext box_ext) (mkScroller scroll_off))
        res.

(** Equivalence between functional and relational semantics. *)
Lemma sticky_step_iff_compute : forall data offset,
  StickyOffsetStep data offset <-> compute_sticky_offset_1d data = offset.
Proof.
  intros [ [static_pos cb_ext box_ext] [scroll_off] ] offset.
  split; intros H.
  - inversion H; subst. reflexivity.
  - simpl in H. subst.
    econstructor; reflexivity.
Qed.

(** ** 3 & 4. Mathematical Invariants & Boundary Constraints *)

(** Invariant 1: Sticky offset is strictly non-negative. *)
Theorem sticky_offset_non_negative : forall data offset,
  StickyOffsetStep data offset ->
  0 <= offset.
Proof.
  intros data offset Hstep.
  inversion Hstep; subst.
  unfold clamp, available_space.
  lia.
Qed.

(** Invariant 2a: Sticky offset is bounded by available containment space (general case). *)
Theorem sticky_offset_bounded_by_available_space : forall static_pos cb_ext box_ext scroll_off offset,
  StickyOffsetStep (mkStickyData (mkConstraints static_pos cb_ext box_ext) (mkScroller scroll_off)) offset ->
  offset <= available_space cb_ext box_ext.
Proof.
  intros static_pos cb_ext box_ext scroll_off offset Hstep.
  inversion Hstep; subst.
  unfold clamp, available_space.
  lia.
Qed.

(** Invariant 2b: Sticky offset is bounded by (cb_extent - box_extent) when the box fits in the CB. *)
Theorem sticky_offset_bounded_by_containment : forall static_pos cb_ext box_ext scroll_off offset,
  cb_ext >= box_ext ->
  StickyOffsetStep (mkStickyData (mkConstraints static_pos cb_ext box_ext) (mkScroller scroll_off)) offset ->
  offset <= cb_ext - box_ext.
Proof.
  intros static_pos cb_ext box_ext scroll_off offset Hfits Hstep.
  inversion Hstep; subst.
  unfold clamp, available_space.
  lia.
Qed.

(** Boundary Constraint: The translated sticky box remains within its containing block rect.
    Specifically, static_pos <= translated_pos and translated_pos + box_ext <= static_pos + cb_ext. *)
Theorem sticky_box_within_containing_block : forall static_pos cb_ext box_ext scroll_off offset,
  cb_ext >= box_ext ->
  StickyOffsetStep (mkStickyData (mkConstraints static_pos cb_ext box_ext) (mkScroller scroll_off)) offset ->
  let translated_pos := static_pos + offset in
  static_pos <= translated_pos /\ translated_pos + box_ext <= static_pos + cb_ext.
Proof.
  intros static_pos cb_ext box_ext scroll_off offset Hfits Hstep translated_pos.
  unfold translated_pos.
  pose proof (sticky_offset_non_negative _ _ Hstep) as Hnonneg.
  pose proof (sticky_offset_bounded_by_containment _ _ _ _ _ Hfits Hstep) as Hbound.
  lia.
Qed.

(** Boundary Constraint: Viewport Scroll Boundary.
    When the scroll_offset is within the active sticky range, the element tracks the scrollport
    exactly (i.e. translated_pos = scroll_offset). *)
Theorem sticky_box_tracks_viewport_in_range : forall static_pos cb_ext box_ext scroll_off offset,
  static_pos <= scroll_off ->
  scroll_off - static_pos <= cb_ext - box_ext ->
  StickyOffsetStep (mkStickyData (mkConstraints static_pos cb_ext box_ext) (mkScroller scroll_off)) offset ->
  static_pos + offset = scroll_off.
Proof.
  intros static_pos cb_ext box_ext scroll_off offset Hlower Hupper Hstep.
  inversion Hstep; subst.
  unfold clamp, available_space.
  lia.
