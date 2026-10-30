### 1. Viewport Containing Block
Per CSS Positioned Layout Module Level 3 §3 (Fixed Positioning), an element with `position: fixed` is positioned relative to its containing block, which—in the absence of ancestor transforms, perspectives, or filters—is established by the continuous media viewport (the initial containing block's layout viewport). 

Within Chromium Blink's layout engine (`BlinkLayoutNG`), the viewport containing block for fixed-positioned elements is defined by:
*   **Origin**: Strictly anchored at $(0, 0)$ in screen/viewport coordinate space.
*   **Dimensions**: Bounded by the layout viewport width and height, $(vw, vh)$, where $vw \ge 0$ and $vh \ge 0$.

---

### 2. Fixed Coordinate Resolution
For a box with `position: fixed` and specified `left` and `top` offsets (assuming `width`/`height` are definite and `right`/`bottom` are `auto`), the static/scroll-adjusted layout tree offsets are bypassed in favor of direct viewport-relative coordinates.

The resolved physical coordinates $(x, y)$ of the box's margin edge relative to the viewport are:
$$x = \text{left}$$
$$y = \text{top}$$

In Blink's paint and compositing stages (`PaintPropertyTreeBuilder`), the offset is applied directly to the viewport space transform node, isolating it from the root scroller's translation matrix.

---

### 3. Invariants
*   **Scroll Invariance**: Let $S = (sx, sy)$ represent the document's visual or layout scroll offset. The screen-space position $P_{\text{screen}}$ of a fixed-positioned box is invariant with respect to $S$:
    $$\forall S_1, S_2, \quad \text{resolve\_fixed}(V, \text{offsets}, S_1) = \text{resolve\_fixed}(V, \text{offsets}, S_2)$$
*   **Origin Identity**: When `left` $= 0$ and `top` $= 0$, the box's top-left corner coincides strictly with the viewport origin $(0,0)$, regardless of the document scroll state.

---

### 4. Formal Verification (`BlinkFixedPositionViewportSemantics.v`)

```coq
(** 
  Audit: Agent 201
  Target: Chromium Blink Fixed Position Viewport Resolution
  Spec: CSS Positioned Layout Module Level 3 §3
*)

Require Import Coq.ZArith.ZArith.
Open Scope Z_scope.

(** 1. Viewport Containing Block *)
Record Viewport : Type := mkViewport {
  vw : Z;
  vh : Z;
  vw_nonneg : 0 <= vw;
  vh_nonneg : 0 <= vh
}.

(** Viewport origin is strictly (0, 0) *)
Definition viewport_origin : (Z * Z) := (0, 0).

(** Document Scroll Offset *)
Record ScrollOffset : Type := mkScrollOffset {
  scroll_x : Z;
  scroll_y : Z
}.

(** CSS Fixed Box Offsets *)
Record FixedOffsets : Type := mkFixedOffsets {
  left : Z;
  top  : Z
}.

(** Resolved Screen-Space Coordinates *)
Record ScreenPosition : Type := mkScreenPosition {
  x : Z;
  y : Z
}.

(** 2. Fixed Coordinate Resolution 
    In Blink, fixed positioning resolves relative to the viewport origin (0,0),
    completely ignoring the passed document ScrollOffset. *)
Definition resolve_fixed_position 
  (v : Viewport) 
  (offsets : FixedOffsets) 
  (s : ScrollOffset) : ScreenPosition :=
  let (origin_x, origin_y) := viewport_origin in
  mkScreenPosition (origin_x + left offsets) (origin_y + top offsets).

(** 3. Theorems & Invariants *)

(** Theorem 1: Direct Coordinate Mapping (x = left, y = top) *)
Theorem fixed_coordinates_exact :
  forall (v : Viewport) (offsets : FixedOffsets) (s : ScrollOffset),
    let pos := resolve_fixed_position v offsets s in
    x pos = left offsets /\ y pos = top offsets.
Proof.
  intros v offsets s.
  unfold resolve_fixed_position, viewport_origin.
  simpl.
  split; reflexivity.
Qed.

(** Theorem 2: Scroll Offset Independence Invariant *)
Theorem fixed_position_scroll_invariant :
  forall (v : Viewport) (offsets : FixedOffsets) (s1 s2 : ScrollOffset),
    resolve_fixed_position v offsets s1 = resolve_fixed_position v offsets s2.
Proof.
  intros v offsets s1 s2.
  unfold resolve_fixed_position.
  reflexivity.
Qed.

(** Theorem 3: Zero Offsets Anchor Strictly to Viewport Origin (0,0) *)
Theorem zero_offsets_at_origin :
  forall (v : Viewport) (s : ScrollOffset),
    let zero_offsets := mkFixedOffsets 0 0 in
    let pos := resolve_fixed_position v zero_offsets s in
    (x pos, y pos) = viewport_origin.
Proof.
  intros v s.
  unfold resolve_fixed_position, viewport_origin.
  simpl.
  reflexivity.
Qed.
```