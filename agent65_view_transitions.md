## 1. Core Data Structures in Blink View Transitions

In Chromium Blink (`third_party/blink/renderer/core/view_transition/`), CSS View Transitions Level 1 is orchestrated by tracking DOM element states across lifecycle updates and synthesizing pseudo-element trees (`::view-transition`, `::view-transition-group()`, `::view-transition-image-pair()`, `::view-transition-old()`, `::view-transition-new()`).

### `ViewTransitionStyleTracker`
The primary state machine managing the lifecycle of a transition (`kIdle`, `kCapturing`, `kCaptured`, `kStarted`, `kFinished`). 
* **Responsibilities**: Maintains `ElementData` maps keyed by ` view-transition-name`. Computes dynamic UA stylesheet rules (`ViewTransitionStyleBuilder`) that apply captured geometry and animations to the `::view-transition-group(*)` pseudo-elements.
* **Key Fields**:
  * `element_data_map_`: `HeapHashMap<AtomicString, Member<ElementData>>` mapping transition names to their captured snapshot state.
  * `captured_name_count_`: Tracks discovered elements to verify uniqueness constraints (duplicate `view-transition-name` values abort the transition per spec).
  * `root_snapshot_id_`: `viz::ViewTransitionElementResourceId` for the root stacking context.

### `ViewTransitionTransitionState` (`viz::ViewTransitionElementResourceId` & `ViewTransitionState`)
Represents the serializable transfer state used across same-document and cross-document (MPA) transitions (`third_party/blink/public/common/frame/view_transition_state.h`).
* **Structure**: Contains a vector of `ViewTransitionElement` structs, the snapshot root size, and device pixel ratio. Allows the browser/GPU process (`viz`) to cache textures from the old document state and bind them to pseudo-element layers in the new state.

### `SnapshotQuad` & Geometry Representations (`ContainerProperties`)
In Blink, captured geometry is stored inside `ViewTransitionStyleTracker::ContainerProperties`:
```cpp
struct ContainerProperties {
  PhysicalSize border_box_size_in_css_space;
  gfx::Transform snapshot_matrix; // Local-to-snapshot-root 4x4 matrix
};
```
Along with `visual_overflow_rect_in_layout_space` (a `PhysicalRect`), this defines the exact geometry of the element’s box and ink overflow relative to the **SnapshotContainingBlock** (the fixed-size viewport origin).

### `ViewTransitionElement`
The wire-format representation of a single named participant (`ViewTransitionStateElement`):
* `tag_name`: The `view-transition-name` identifier.
* `border_box_size_in_css_space`: `gfx::SizeF` representing width and height.
* `viewport_matrix`: `gfx::Transform` mapping the element's local coordinate space to the snapshot root coordinate space.
* `overflow_rect_in_layout_space`: `gfx::RectF` for ink overflow clipping/quad sizing.
* `snapshot_id`: The GPU resource ID (`viz::ViewTransitionElementResourceId`) pointing to the cached render pass texture.
* `captured_rect_in_layout_space`: Optional sub-rect when clipping large elements to viewport bounds.

---

## 2. Snapshot Geometry Capture

During the **Capture Old** and **Capture New** phases (Section 6.2 & 6.4 of CSS View Transitions Level 1), Blink executes `ViewTransitionStyleTracker::RunPostPrePaintSteps()`.

### Recording Border-Box Rects in Document/Snapshot Space
For each transitioning element $e$:
1. **Box Sizing**: Blink queries the `LayoutBoxModelObject` to compute `border_box_size_in_css_space` $(w, h)$. The width and height are converted from `PhysicalSize` (fixed-point `LayoutUnit`, $1/64\text{th}$ px) into CSS pixels by dividing by the `effective_zoom` factor.
2. **Coordinate Space Mapping**: The specification defines the **Snapshot Containing Block (SCB)** as an origin-aligned rectangle matching the layout viewport if fixed, inclusive of scrollbars. Blink computes `snapshot_matrix` ($M \in \mathbb{R}^{4\times 4}$, reduced to 2D affine $\mathbb{R}^{3\times 3}$ for planar elements) via `GeometryMapper::SourceToDestinationProjection()`:
   $$M_{\text{snapshot}} = M_{\text{root}\to\text{SCB}} \cdot M_{\text{element}\to\text{root}}$$
   This matrix accounts for CSS `transform`, scrolling offsets, and ancestor layout positions.

### Computing Delta Affine Transforms
In the `kStarted` phase, Blink generates keyframes and dynamic inline styles for `::view-transition-group(name)`.
* **Old State ($t = 0$)**: The UA style sheet sets the initial geometry of `::view-transition-group(name)` to match the old state directly:
  $$\text{width}_0 = w_{\text{old}}, \quad \text{height}_0 = h_{\text{old}}, \quad M_0 = M_{\text{old}}$$
* **New State ($t = 1$)**: If the element exists in the new DOM, Blink updates the live pseudo-element rule for `::view-transition-group(name)` on every frame (`UpdateContainerStyles`), setting its target state to:
  $$\text{width}_1 = w_{\text{new}}, \quad \text{height}_1 = h_{\text{new}}, \quad M_1 = M_{\text{new}}$$
* **Animation Keyframes**: Blink injects a `@keyframes -ua-view-transition-group-anim-<name>` rule setting the `from` keyframe to `transform: M_old; width: w_old; height: h_old;`:
  $$\Delta M = M_{\text{new}} \cdot M_{\text{old}}^{-1} \quad (\text{implicitly solved via CSS Transform Interpolation})$$
* **Image Pair Aspect-Ratio Scaling**: Inside the group, `::view-transition-old(name)` has intrinsic texture size $(w_{\text{old}}, h_{\text{old}})$ and CSS `width: 100%; height: 100%`, causing an implicit scale transform $S(t) = \text{diag}(w(t)/w_{\text{old}}, h(t)/h_{\text{old}})$ as the group box resizes.

---

## 3. Layer Group Transformation and Interpolation

Across transition progress $t \in [0, 1]$ (after applying the CSS timing function $\tau: [0,1] \to \mathbb{R}$, clamped to $[0,1]$ for monotonic easing), the group container state $G(t) = (w(t), h(t), M(t))$ is evaluated by the compositor/animation engine:

### 1. Size Interpolation
Width and height are linearly interpolated in CSS pixel space:
$$w(t) = (1 - t) \cdot w_{\text{old}} + t \cdot w_{\text{new}}$$
$$h(t) = (1 - t) \cdot h_{\text{old}} + t \cdot h_{\text{new}}$$

### 2. Transform Matrix Interpolation
For 2D affine transforms represented as $M = \begin{pmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{pmatrix}$, CSS Transforms Level 1 (used by Blink's `TransformationMatrix::Blend`) decomposes $M_{\text{old}}$ and $M_{\text{new}}$ into translation $T = (e, f)$, scale $S = (s_x, s_y)$, skew $K$, and rotation angle $\theta$:
* **Translation**: $T(t) = (1 - t) T_{\text{old}} + t T_{\text{new}}$
* **Scale**: $S(t) = (1 - t) S_{\text{old}} + t S_{\text{new}}$
* **Rotation/Skew**: Interpolated linearly in parameter space, then recomposed:
  $$M(t) = \text{Recompose}(T(t), \theta(t), K(t), S(t))$$
When both matrices contain only translation and positive scale ($b = c = 0, a > 0, d > 0$), matrix decomposition interpolation reduces to component-wise linear interpolation (LERP) of the matrix entries:
$$M(t) = (1 - t) M_{\text{old}} + t M_{\text{new}}$$

---

## 4. Mathematical Invariants

1. **Bounding Rect Non-Negativity**:
   For any valid layout box, $w_{\text{old}} \ge 0$, $h_{\text{old}} \ge 0$, $w_{\text{new}} \ge 0$, and $h_{\text{new}} \ge 0$. By convexity of $[0, \infty)$ under linear combinations with $t \in [0, 1]$, the interpolated group dimensions satisfy:
   $$\forall t \in [0, 1], \quad w(t) \ge 0 \land h(t) \ge 0$$

2. **Interpolation Boundary Preservation**:
   * At $t = 0$ (transition start): $G(0) = (w_{\text{old}}, h_{\text{old}}, M_{\text{old}})$, matching the exact captured old snapshot geometry.
   * At $t = 1$ (transition end): $G(1) = (w_{\text{new}}, h_{\text{new}}, M_{\text{new}})$, matching the exact captured new snapshot geometry before dropping the pseudo-element tree.

3. **Determinism**:
   Given fixed old and new `ContainerProperties` and a progress parameter $t$, the resulting group layer state is uniquely determined.

4. **Identity Preservation (Stationary Element Invariant)**:
   If an element does not change geometry between old and new states ($S_{\text{old}} = S_{\text{new}}$), then for all $t \in [0, 1]$, $G(t) = S_{\text{old}}$.

---

## 5. Formalization in Rocq / Coq (`BlinkViewTransitionSnapshotSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the snapshot data structures, affine matrix interpolation, size interpolation, and proves the core mathematical invariants using `Reals` and `Lra`.

```coq
(** * BlinkViewTransitionSnapshotSemantics.v
    Formalization of Chromium Blink CSS View Transitions Level 1
    Snapshot Geometry Capture and Layer Group Interpolation. *)

Require Import Coq.Reals.Reals.
Require Import Coq.Strings.String.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lra.

Open Scope R_scope.
Import ListNotations.

(** ** 1. Core Geometry and Blink Data Structures *)

(** 2D Size in CSS pixel space (gfx::SizeF / PhysicalSize) *)
Record SizeF : Type := mkSizeF {
  width  : R;
  height : R
}.

(** Non-negativity predicate for bounding sizes *)
Definition valid_size (s : SizeF) : Prop :=
  0 <= width s /\ 0 <= height s.

(** 2D Rect in layout space (gfx::RectF / PhysicalRect) *)
Record RectF : Type := mkRectF {
  origin_x : R;
  origin_y : R;
  rect_size : SizeF
}.

Definition valid_rect (r : RectF) : Prop :=
  valid_size (rect_size r).

(** 2D Affine Transform Matrix (subset of gfx::Transform)
    [ m11  m12  tx ]
    [ m21  m22  ty ]
    [  0    0    1 ] *)
Record AffineTransform2D : Type := mkAffine {
  m11 : R; m12 : R; tx : R;
  m21 : R; m22 : R; ty : R
}.

Definition identity_transform : AffineTransform2D :=
  mkAffine 1 0 0
           0 1 0.

(** Matrix multiplication for 2D affine transforms: M_a * M_b *)
Definition compose_affine (a b : AffineTransform2D) : AffineTransform2D :=
  mkAffine
    (m11 a * m11 b + m12 a * m21 b)
    (m11 a * m12 b + m12 a * m22 b)
    (m11 a * tx b  + m12 a * ty b  + tx a)
    (m21 a * m11 b + m22 a * m21 b)
    (m21 a * m12 b + m22 a * m22 b)
    (m21 a * tx b  + m22 a * ty b  + ty a).

(** Point transformation in 2D space *)
Definition transform_point (m : AffineTransform2D) (x y : R) : (R * R) :=
  (m11 m * x + m12 m * y + tx m,
   m21 m * x + m22 m * y + ty m).

(** Blink ViewTransitionStyleTracker::ContainerProperties *)
Record ContainerProperties : Type := mkContainerProps {
  border_box_size_in_css_space : SizeF;
  snapshot_matrix              : AffineTransform2D
}.

Definition valid_container_props (cp : ContainerProperties) : Prop :=
  valid_size (border_box_size_in_css_space cp).

(** Blink ViewTransitionElement (serializable state per named element) *)
Record ViewTransitionElement : Type := mkVTElement {
  tag_name                        : string;
  vt_container_props              : ContainerProperties;
  overflow_rect_in_layout_space   : RectF;
  snapshot_id                     : nat
}.

(** Blink ViewTransitionStyleTracker::ElementData *)
Record ElementData : Type := mkElementData {
  name                : string;
  old_snapshot        : option ContainerProperties;
  new_snapshot        : option ContainerProperties;
  visual_overflow_old : option RectF;
  visual_overflow_new : option RectF
}.

(** Blink ViewTransition lifecycle phases *)
Inductive TransitionPhase : Type :=
  | kIdle
  | kCapturing
  | kCaptured
  | kStarted
  | kFinished.

(** Blink ViewTransitionStyleTracker state *)
Record ViewTransitionStyleTracker : Type := mkStyleTracker {
  phase                 : TransitionPhase;
  element_data_map      : list ElementData;
  snapshot_root_size    : SizeF
}.

(** ** 2. Linear Interpolation (LERP) Operations *)

Definition lerp_R (t a b : R) : R :=
  (1 - t) * a + t * b.

Definition lerp_size (t : R) (s_old s_new : SizeF) : SizeF :=
  mkSizeF
    (lerp_R t (width s_old) (width s_new))
    (lerp_R t (height s_old) (height s_new)).

Definition lerp_affine (t : R) (m_old m_new : AffineTransform2D) : AffineTransform2D :=
  mkAffine
    (lerp_R t (m11 m_old) (m11 m_new))
    (lerp_R t (m12 m_old