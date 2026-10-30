### 1. Core Data Structures in Blink Scroll Anchoring

In Chromium's Blink rendering engine (`third_party/blink/renderer/core/layout/scroll_anchor.h` and `.cc`), Scroll Anchoring is implemented to satisfy **W3C CSS Scroll Anchoring Module Level 1 §3**. The primary structures managing the anchor lifecycle across layout passes are:

1. **`ScrollAnchor`**:
   The controller class owned by a `ScrollableArea` (such as `PaintLayerScrollableArea` or `RootFrameViewport`). It tracks:
   * `anchor_object_` (`LayoutObject*`): The currently selected DOM/layout node serving as the anchor.
   * `saved_relative_offset_` (`PhysicalOffset`): The offset of the `anchor_object_`'s reference point relative to the scrollable area's visible content rect at the time the anchor was saved (prior to layout).
   * `corner_` (`Corner`): Which corner of the anchor object's bounding box is tracked (`kTopLeft` or `kTopRight`, depending on writing mode/direction).

2. **`AnchorCandidate`** (Implicitly represented during `ExamineResult` traversal):
   During the candidate selection tree walk (`ScrollAnchor::FindAnchorRecursive`), candidate `LayoutObject` nodes are evaluated against the scroller's optimal viewing region. The traversal produces an `ExamineResult` containing:
   * `status` (`kSkip`, `kContinue`, `kReturn`, `kConstrain`).
   * `corner` (`Corner`).
   * Candidate rect geometry calculated via `ScrollAnchor::ComputeRelativeOffset`.

3. **`ScrollAnchorData`** (Exposed to Compositor / Tracing / Web APIs):
   A serializable summary struct containing the anchor's selector/node identity, `saved_relative_offset_`, and accumulated adjustments (`scroll_offset_delta`) to synchronize scroll anchoring state between Blink's main thread and the CC (Compositor) thread.

---

### 2. Drift Calculation Algorithm

Per **W3C Scroll Anchoring §3.2 (Scroll Adjustment)**, after a layout update occurs, the engine calculates how far the anchor node has moved relative to the scroll container's scroll origin.

Let $R_{\text{saved}}$ be the anchor bounding box's offset relative to the scroller's origin before layout, and $R_{\text{current}}$ be its offset relative to the scroller's origin after layout (under the *current* unadjusted scroll offset $S_{\text{old}}$).

In the block-flow direction (simplified to vertical y-axis `.top` for standard `horizontal-tb` writing modes):

$$\Delta y = R_{\text{current}}.\text{top} - R_{\text{saved}}.\text{top}$$

In Blink (`ScrollAnchor::ComputeScrollDelta`), this is computed by comparing the current relative offset of `anchor_object_` in the scroller's visible viewport against `saved_relative_offset_`:
* If `saved_relative_offset_` was captured at scroll offset $S_{\text{old}}$ as $P_{\text{visual\_old}} = R_{\text{saved}}.\text{top} - S_{\text{old}}$, and after layout at the same $S_{\text{old}}$ the new visual position is $P_{\text{visual\_current}} = R_{\text{current}}.\text{top} - S_{\text{old}}$, the drift $\Delta y$ is identically:
$$\Delta y = P_{\text{visual\_current}} - P_{\text{visual\_old}} = (R_{\text{current}}.\text{top} - S_{\text{old}}) - (R_{\text{saved}}.\text{top} - S_{\text{old}}) = R_{\text{current}}.\text{top} - R_{\text{saved}}.\text{top}$$

---

### 3. Scroll Adjustment Application

When $\Delta y \neq 0$, Blink's `ScrollAnchor::Adjust()` applies the compensating delta to the `ScrollableArea`'s scroll offset:

$$S_{\text{new}} = S_{\text{old}} + \Delta y$$

*(Note: In practice, $S_{\text{new}}$ is subsequently clamped to the valid scroll range $[S_{\min}, S_{\max}]$, though in the unconstrained interior domain of the scroller, the identity holds strictly).*

---

### 4. Mathematical Invariants

1. **Exact Visual Compensation (Zero Relative Visual Movement)**:
   The visual position of the anchor node relative to the viewport top is given by $V(R, S) = R.\text{top} - S$.
   Before layout: $V_{\text{old}} = R_{\text{saved}}.\text{top} - S_{\text{old}}$.
   After layout and scroll adjustment: $V_{\text{new}} = R_{\text{current}}.\text{top} - S_{\text{new}}$.
   Substituting $S_{\text{new}} = S_{\text{old}} + (R_{\text{current}}.\text{top} - R_{\text{saved}}.\text{top})$:
   $$V_{\text{new}} - V_{\text{old}} = 0$$
   The anchor remains at the exact same pixel coordinate on the user's screen.

2. **Zero-Drift Identity**:
   If layout does not mutate the block offset of the anchor node ($R_{\text{current}}.\text{top} = R_{\text{saved}}.\text{top}$), then $\Delta y = 0$ and $S_{\text{new}} = S_{\text{old}}$.

3. **Determinism**:
   For any given initial state (`ScrollAnchorData`) and post-layout geometry (`Rect`), the resulting scroll adjustment and new scroll offset are uniquely determined.

---

### 5. Rocq / Coq Formalization (`BlinkScrollAnchoringSemantics.v`)

Below is a self-contained, fully verified Rocq (Coq) formalization encoding the data structures, semantics, and proofs of the core invariants.

```coq
(** * BlinkScrollAnchoringSemantics.v
    Formalization of Chromium Blink Scroll Anchoring vs W3C Scroll Anchoring Level 1 §3
    Agent 78 Audit Artifact *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Micromega.Lia.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Node identifier representing a DOM/LayoutObject reference. *)
Definition NodeId := nat.

(** Axis-aligned bounding box in layout coordinates (relative to scrollable overflow origin). *)
Record LayoutRect : Type := mkLayoutRect {
  rect_top    : Z;
  rect_left   : Z;
  rect_width  : Z;
  rect_height : Z
}.

(** Corner selection per Blink's ScrollAnchor::Corner. *)
Inductive AnchorCorner : Type :=
  | CornerTopLeft
  | CornerTopRight.

(** Candidate evaluated during FindAnchorRecursive traversal. *)
Record AnchorCandidate : Type := mkAnchorCandidate {
  cand_node_id : NodeId;
  cand_rect    : LayoutRect;
  cand_corner  : AnchorCorner
}.

(** Saved state in Blink's ScrollAnchor / ScrollAnchorData prior to layout. *)
Record ScrollAnchorData : Type := mkScrollAnchorData {
  anchor_node       : NodeId;
  saved_anchor_rect : LayoutRect;
  anchor_corner     : AnchorCorner;
  scroll_offset_old : Z
}.

(** State of the ScrollableArea and its ScrollAnchor after adjustment. *)
Record ScrollAnchorState : Type := mkScrollAnchorState {
  state_data        : ScrollAnchorData;
  current_rect      : LayoutRect;
  drift_delta       : Z;
  scroll_offset_new : Z
}.

(** ** 2. Drift Calculation & Scroll Adjustment Algorithms *)

(** W3C §3.2 / Blink ScrollAnchor::ComputeScrollDelta:
    delta = current_anchor_rect.top - saved_anchor_rect.top *)
Definition compute_drift (saved_rect current_rect : LayoutRect) : Z :=
  (rect_top current_rect) - (rect_top saved_rect).

(** W3C §3.2 / Blink ScrollAnchor::Adjust:
    scroll_offset_new = scroll_offset_old + delta *)
Definition apply_scroll_adjustment (scroll_old delta : Z) : Z :=
  scroll_old + delta.

(** Visual offset of a rect's top edge relative to the viewport top at scroll offset S. *)
Definition visual_viewport_offset (r : LayoutRect) (scroll_offset : Z) : Z :=
  (rect_top r) - scroll_offset.

(** Complete operational step of a ScrollAnchor adjustment pass. *)
Inductive ScrollAnchorStep (data : ScrollAnchorData) (curr_rect : LayoutRect) : ScrollAnchorState -> Prop :=
  | Step_Adjust :
      forall (delta s_new : Z),
      delta = compute_drift (saved_anchor_rect data) curr_rect ->
      s_new = apply_scroll_adjustment (scroll_offset_old data) delta ->
      ScrollAnchorStep data curr_rect (mkScrollAnchorState data curr_rect delta s_new).

(** ** 3. Mathematical Invariants & Proofs *)

(** Invariant 1a: Scroll adjustment exactly preserves the visual viewport offset of the anchor. *)
Theorem scroll_adjustment_preserves_visual_position :
  forall (data : ScrollAnchorData) (curr_rect : LayoutRect) (st : ScrollAnchorState),
    ScrollAnchorStep data curr_rect st ->
    visual_viewport_offset curr_rect (scroll_offset_new st) =
    visual_viewport_offset (saved_anchor_rect data) (scroll_offset_old data).
Proof.
  intros data curr_rect st Hstep.
  inversion Hstep; subst.
  unfold visual_viewport_offset, apply_scroll_adjustment, compute_drift.
  simpl.
  lia.
Qed.

(** Invariant 1b: The relative visual movement (visual drift after adjustment) is strictly zero. *)
Theorem relative_visual_movement_is_zero :
  forall (data : ScrollAnchorData) (curr_rect : LayoutRect) (st : ScrollAnchorState),
    ScrollAnchorStep data curr_rect st ->
    (visual_viewport_offset curr_rect (scroll_offset_new st)) -
    (visual_viewport_offset (saved_anchor_rect data) (scroll_offset_old data)) = 0.
Proof.
  intros data curr_rect st Hstep.
  rewrite (scroll_adjustment_preserves_visual_position data curr_rect st Hstep).
  lia.
Qed.

(** Invariant 2: Zero-Drift Identity. When the anchor's top coordinate does not move,
    drift is zero and the scroll offset remains unchanged. *)
Theorem zero_drift_when_anchor_stationary :
  forall (data : ScrollAnchorData) (curr_rect : LayoutRect) (st : ScrollAnchorState),
    ScrollAnchorStep data curr_rect st ->
    rect_top curr_rect = rect_top (saved_anchor_rect data) ->
    drift_delta st = 0 /\ scroll_offset_new st = scroll_offset_old data.
Proof.
  intros data curr_rect st Hstep Hsame_top.
  inversion Hstep; subst.
  unfold compute_drift, apply_scroll_adjustment.
  simpl.
  split; lia.
Qed.

(** Invariant 3: Determinism of the Scroll Anchoring adjustment step. *)
Theorem scroll_anchor_step_deterministic :
  forall (data : ScrollAnchorData) (curr_rect : LayoutRect) (st1 st2 : ScrollAnchorState),
    ScrollAnchorStep data curr_rect st1 ->
    ScrollAnchorStep data curr_rect st2 ->
    st1 = st2.
Proof.
  intros data curr_rect st1 st2 Hstep1 Hstep2.
  inversion Hstep1; subst.
  inversion Hstep2; subst.
  reflexivity.
Qed.

(** Invariant 4: Compositionality across multiple sequential layout shifts.
    Two consecutive layout shifts and adjustments equal a single adjustment from the initial state. *)
Theorem scroll_adjustment_compositional :
  forall (r0 r1 r2 : LayoutRect) (s0 : Z),
    let d1 := compute_drift r0 r1 in
    let s1 := apply_scroll_adjustment s0 d1 in
    let d2 := compute_drift r1 r2 in
    let s2 := apply_scroll_adjustment s1 d2 in
    let d_total := compute_drift r0 r2 in
    s2 = apply_scroll_adjustment s0 d_total.
Proof.
  intros r0 r1 r2 s0 d1 s1 d2 s2 d_total.
  unfold s2, d2, s1, d1, d_total, apply_scroll_adjustment, compute_drift.
  lia.
Qed.
```