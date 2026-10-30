### 1. Core Data Structures in Blink 2D Sticky Positioning

In Chromium's Blink engine (specifically within `third_party/blink/renderer/core/layout/layout_box_model_object.cc` and `compositing/composited_layer_mapping.cc`), multi-axis sticky positioning is computed by mapping logical CSS insets (`top`, `right`, `bottom`, `left`, `inset-inline-*`, `inset-block-*`) into physical 2D geometry relative to an ancestor scroll container and a containing block.

*   **`PhysicalOffset` / `gfx::Vector2dF`**: Represents the concrete 2D displacement $(\Delta x, \Delta y)$ in physical coordinates (typically represented via `LayoutUnit`, a 26.6 fixed-point integer format, or float during compositing).
*   **`PhysicalRect` & `LogicalRect`**: Represent axis-aligned bounding boxes $[x, x + w] \times [y, y + h]$. While CSS resolution occurs in flow-relative `LogicalRect` coordinates, sticky constraints are converted to physical rects (`scroll_container_relative_containing_block_rect` and `scroll_container_relative_sticky_box_rect`) prior to evaluating the scroll shift.
*   **`StickyPositionScrollingConstraints` (historically `StickyPositionOffsetData`)**: The core data carrier passed between main-thread layout and the compositor thread (`cc::StickyPositionNodeData`). It encapsulates:
    *   `is_anchored_left`, `is_anchored_right`, `is_anchored_top`, `is_anchored_bottom`: Boolean flags indicating active constraints.
    *   `left_offset`, `right_offset`, `top_offset`, `bottom_offset`: Resolved physical insets.
    *   `scroll_container_relative_sticky_box_rect`: The unshifted border box of the sticky element in the scroll container's content space ($B$).
    *   `scroll_container_relative_containing_block_rect`: The content box of the containing block (adjusted by the sticky element's margins) in the scroll container's content space ($C$).
    *   `nearest_layer_shifting_sticky_box` / `nearest_layer_shifting_containing_block`: Compositor handles for chained/nested sticky elements.
*   **`ScrollRange2D` (Implicitly `[0, MaxScrollOffsetX] x [0, MaxScrollOffsetY]`)**: The valid 2D scroll offset domain of the ancestor `PaintLayerScrollableArea`, combined with its visible viewport rect (adjusted by `scroll-padding`) to form the dynamic `sticky_view_rect` ($V$).

---

### 2. 2D Offset Computation

Per CSS Position Level 3 §6.3, multi-axis sticky positioning acts independently along the horizontal ($X$) and vertical ($Y$) physical axes. Because the sticky view rectangle $V$, the containing block constraint rectangle $C$, and the sticky box $B$ are all axis-aligned rectangles, their 2D Cartesian product decomposes cleanly into two orthogonal 1D interval problems:

$$R_{2D} = I_X \times I_Y \implies \Delta \mathbf{p} = (\Delta x, \Delta y)$$

For a given scroll offset $\mathbf{s} = (s_x, s_y)$, the scrollport (viewport) defines the 2D sticky view rectangle $V(\mathbf{s}) = [V_x^{\min}, V_x^{\max}] \times [V_y^{\min}, V_y^{\max}]$.

#### Independent Axis Evaluation
Let $B = [B_x^{\min}, B_x^{\max}] \times [B_y^{\min}, B_y^{\max}]$ be the unshifted sticky box, and $C = [C_x^{\min}, C_x^{\max}] \times [C_y^{\min}, C_y^{\max}]$ be the margin-adjusted containing block box.

1.  **Horizontal (Inline in horizontal-tb) Shift ($\Delta x$)**:
    *   **Right constraint ($o_R$)**: If active, the box must not cross $V_x^{\max} - o_R$. If $B_x^{\max} > V_x^{\max} - o_R$, we require a negative shift:
        $$\delta_{R} = \min\left(0, (V_x^{\max} - o_R) - B_x^{\max}\right)$$
        Clamped by the containing block's left edge ($C_x^{\min}$):
        $$\Delta x_R = \max\left(\delta_{R}, C_x^{\min} - B_x^{\min}\right)$$
    *   **Left constraint ($o_L$)**: Applied sequentially after the right constraint (giving it precedence). Let $B'_x = B_x + \Delta x_R$. If $B'^{\min}_x < V_x^{\min} + o_L$, we require a positive shift:
        $$\delta_{L} = \max\left(0, (V_x^{\min} + o_L) - B_x^{\min}\right)$$
        Clamped by the containing block's right edge ($C_x^{\max}$):
        $$\Delta x = \min\left(\Delta x_R + \delta_{L}, C_x^{\max} - B_x^{\max}\right)$$
        *(Note: Blink computes this by evaluating the opposing constraint first, or by clamping the final combined shift such that the start edge wins).*

2.  **Vertical (Block in horizontal-tb) Shift ($\Delta y$)**:
    *   **Bottom constraint ($o_B$)**: Pulls the box up ($\le 0$), clamped by the containing block's top edge ($C_y^{\min} - B_y^{\min}$).
    *   **Top constraint ($o_T$)**: Pushes the box down ($\ge 0$), clamped by the containing block's bottom edge ($C_y^{\max} - B_y^{\max}$).

---

### 3. Handling Conflicting Constraints

Over-constrained sticky boxes occur in two scenarios along any given axis:
1.  **Viewport Conflict**: Both opposing insets are specified (e.g., `left: 20px; right: 20px`), and the available sticky view span $(V_x^{\max} - V_x^{\min}) - (o_L + o_R)$ is smaller than the sticky box width $(B_x^{\max} - B_x^{\min})$.
2.  **Containing Block Conflict**: The sticky box is strictly larger than its containing block along an axis ($B_{\text{size}} > C_{\text{size}}$).

#### Resolution Rules (CSS Position 3 §6.3 & Blink Implementation)
*   **Sequential Precedence**: In Blink (`StickyPositionScrollingConstraints::ComputeStickyOffset`), opposing constraints are evaluated sequentially:
    *   Along $X$: **Right** is evaluated first, then **Left** is evaluated and overrides Right if they conflict (assuming LTR / default writing mode).
    *   Along $Y$: **Bottom** is evaluated first, then **Top** is evaluated and overrides Bottom.
*   **Containing Block Clamp Asymmetry**: When $B_{\text{size}} > C_{\text{size}}$, the standard clamping interval $[C^{\min} - B^{\min}, C^{\max} - B^{\max}]$ becomes inverted (the lower bound exceeds the upper bound). Blink avoids undefined behavior by only clamping the shift in the *direction of motion*:
    *   A positive shift (pushed by `left` or `top`) is only clamped by the maximum bound: $\Delta^+ \le \max(0, C^{\max} - B^{\max})$.
    *   A negative shift (pulled by `right` or `bottom`) is only clamped by the minimum bound: $\Delta^- \ge \min(0, C^{\min} - B^{\min})$.

---

### 4. Mathematical Invariants

1.  **Orthogonal Decomposition**: The 2D sticky offset operator $\Phi_{2D}$ is strictly the Cartesian product of the 1D sticky offset operators:
    $$\Phi_{2D}(V, C, B) = (\Phi_{1D}(V_X, C_X, B_X), \Phi_{1D}(V_Y, C_Y, B_Y))$$
2.  **Containing Block Containment**: Provided the unshifted sticky box $B$ is initially contained within the containing block $C$ ($C^{\min} \le B^{\min} \land B^{\max} \le C^{\max}$ on both axes), the shifted sticky box $B + \Delta \mathbf{p}$ is guaranteed to remain completely within $C$:
    $$B + \Phi_{2D}(V, C, B) \subseteq C$$
3.  **Zero-Motion Bounds**: Along each axis, if $B \subseteq C$, the shift is bounded by:
    $$C_x^{\min} - B_x^{\min} \le \Delta x \le C_x^{\max} - B_x^{\max} \quad \land \quad C_y^{\min} - B_y^{\min} \le \Delta y \le C_y^{\max} - B_y^{\max}$$
4.  **Determinism**: $\Phi_{2D}$ is a pure, total mathematical function of the input geometries and constraints.
5.  **Projective Idempotence**: Once the box $B$ is shifted to $B' = B + \Phi_{2D}(V, C, B)$, re-evaluating the sticky constraint on the already-shifted box $B'$ with zeroed-out previous offsets yields a net additional shift of $(0, 0)$:
    $$\Phi_{2D}(V, C, B + \Phi_{2D}(V, C, B)) = (0, 0)$$

---

### 5. Formalization in Rocq / Coq (`BlinkStickyMultiAxisSemantics.v`)

The following complete, self-contained Rocq (Coq) formalization encodes the 1D and 2D data structures, Blink's exact clamping and conflict-resolution semantics, and proves the required invariants using `lia`.

```coq
(** * BlinkStickyMultiAxisSemantics.v
    Formal Audit of Chromium Blink Multi-Axis Sticky Positioning
    against CSS Positioned Layout Module Level 3 (Section 6.3).
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Core Geometric & Constraint Data Structures *)

(** 2D Physical Offset (models blink::PhysicalOffset / gfx::Vector2dF) *)
Record PhysicalOffset : Type := mkOffset {
  dx : Z;
  dy : Z
}.

(** 1D Interval [min_pos, max_pos] *)
Record Interval1D : Type := mkInterval {
  min_pos : Z;
  max_pos : Z
}.

(** Well-formedness of a 1D interval (non-negative extent) *)
Definition wf_interval (I : Interval1D) : Prop :=
  min_pos I <= max_pos I.

(** 1D Inclusion: I1 is contained within I2 *)
Definition sub_interval (I1 I2 : Interval1D) : Prop :=
  min_pos I2 <= min_pos I1 /\ max_pos I1 <= max_pos I2.

(** Shift a 1D interval by a scalar delta *)
Definition shift_interval (I : Interval1D) (d : Z) : Interval1D :=
  mkInterval (min_pos I + d) (max_pos I + d).

(** 2D Axis-Aligned Bounding Box (models blink::PhysicalRect / LogicalRect) *)
Record Rect2D : Type := mkRect2D {
  rect_x : Interval1D;
  rect_y : Interval1D
}.

Definition wf_rect2D (R : Rect2D) : Prop :=
  wf_interval (rect_x R) /\ wf_interval (rect_y R).

Definition sub_rect2D (R1 R2 : Rect2D) : Prop :=
  sub_interval (rect_x R1) (rect_x R2) /\ sub_interval (rect_y R1) (rect_y R2).

Definition shift_rect2D (R : Rect2D) (o : PhysicalOffset) : Rect2D :=
  mkRect2D (shift_interval (rect_x R) (dx o))
           (shift_interval (rect_y R) (dy o)).

(** 1D Sticky Constraints (models single-axis projection of StickyPositionScrollingConstraints)
    - start_inset: left (X) or top (Y)
    - end_inset:   right (X) or bottom (Y) *)
Record StickyAxisConstraints : Type := mkAxisConstraints {
  start_inset : option Z;
  end_inset   : option Z
}.

(** 2D Sticky Position Offset Data *)
Record StickyPositionOffsetData : Type := mkStickyData {
  constraints_x : StickyAxisConstraints;
  constraints_y : StickyAxisConstraints;
  sticky_box_rect : Rect2D;
  containing_block_rect : Rect2D
}.

(** ** 2. Blink 1D & 2D Offset Computation *)

(** Blink evaluates the end constraint (right / bottom) first, pulling the box
    in the negative direction, clamped by the containing block's start edge.
    Then it evaluates the start constraint (left / top), pushing the box in the
    positive direction, clamped by the containing block's end edge. *)

Definition compute_end_delta (end_opt : option Z) (view cb box : Interval1D) : Z :=
  match end_opt with
  | None => 0
  | Some o_end =>
      let available_end := max_pos view - o_end in
      let raw_pull := Z.min 0 (available_end - max_pos box) in
      let min_allowed_shift := min_pos cb - min_pos box in
      Z.max raw_pull min_allowed_shift
  end.

Definition compute_start_delta (start_opt : option Z) (view cb box_after_end : Interval1D) : Z :=
  match start_opt with
  | None => 0
  | Some o_start =>
      let available_start := min_pos view + o_start in
      let raw_push := Z.max 0 (available_start - min_pos box_after_end) in
      let max_allowed_shift := max_pos cb - max_pos box_after_end in
      Z.min raw_push max_allowed_shift
  end.

(** Complete 1D Sticky Offset computation *)
Definition compute_1d_sticky_offset
  (c : StickyAxisConstraints) (view cb box : Interval1D) : Z :=
  let d_end := compute_end_delta (end_inset c) view cb box in
  let box'  := shift_interval box d_end in
  let d_start := compute_start_delta (start_inset c) view cb box' in
  d_end + d_start.

(** Complete 2D Multi-Axis Sticky Offset computation *)
Definition compute_2d_sticky_offset
  (data : StickyPositionOffsetData) (scroll_view : Rect2D) : PhysicalOffset :=
  let dx_val := compute_1d_sticky_offset
                  (constraints_x data)
                  (rect_x scroll_view)
                  (rect_x (containing_block_rect data))
