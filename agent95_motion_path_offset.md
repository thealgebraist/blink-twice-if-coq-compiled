### 1. Core Data Structures in Blink Motion Path Evaluation

In Chromium's Blink rendering engine (`third_party/blink/renderer/core/style/` and `core/layout/`), motion path evaluation is driven by `ComputedStyle::ApplyMotionPathTransform` alongside path geometry helpers in `Path` and `StyleOffsetRotation`:

*   **`OffsetPath` (`OffsetPathOperation`)**: Abstract base class representing the `offset-path` CSS property (`CoordBox`, `ShapeOffsetPathOperation`, `GeometryBox`, or `RayOffsetPathOperation`). This is lowered to an underlying platform `blink::Path` (wrapping an `SkPath` / `SkContourMeasure`).
*   **`LengthPercentage` (`blink::Length`)**: Represents `offset-distance`. It is a tagged union holding a `Fixed` scalar (in CSS pixels), a `Percent` scalar ($p \in \mathbb{R}$), or a `CalculationValue` (`calc()`), which evaluates linear combinations of lengths and percentages against the total path length $L$.
*   **`PathPosition` (`PointAndTangent`)**: Returned by `Path::PointAndNormalAtLength(float length)`. It is a struct holding:
    $$\text{PointAndTangent} = \{ \text{point}: (x, y) \in \mathbb{R}^2, \text{tangentAngle}: \theta \in [-180^\circ, 180^\circ] \}$$
*   **`StyleOffsetRotation`**: Represents `offset-rotate`. It contains a `RotationType` enum (`kAuto`, `kFixed`) and an angle $\alpha \in \mathbb{R}$ (in degrees). Note that `reverse` is desugared at parse/style-builder time into `kAuto` with $\alpha + 180^\circ$.
*   **`MotionTransform` (`gfx::Transform`)**: A $4 \times 4$ (or affine $2\text{D}$ $3 \times 3$) column-major homogeneous transformation matrix accumulated into the element's current transform list during `ComputedStyle::ApplyTransform`.

---

### 2. Distance Along Path Calculation

Given a resolved `Path` with total geometric arc length $L = \text{Path::length}() \ge 0$ and an `offset-distance` represented as `Length`, Blink resolves the unconstrained distance $d_{\text{raw}}$ via `FloatValueForLength(offset_distance, L)`:
$$d_{\text{raw}} = \begin{cases} v & \text{if Fixed}(v) \\ \frac{p}{100} \cdot L & \text{if Percent}(p) \\ v + \frac{p}{100} \cdot L & \text{if Calc}(v, p) \end{cases}$$

Per W3C Motion Path Module Level 1 §2.2 and Blink's `Path::PointAndNormalAtLength`, $d_{\text{raw}}$ is mapped to the effective arc-length parameter $s \in [0, L]$ depending on whether the path is closed:

1.  **degenerate Path ($L = 0$)**:
    $$s = 0$$
2.  **Open Path ($\text{IsClosed}() = \text{false}, L > 0$)**: Clamping semantics apply:
    $$s = \min(\max(d_{\text{raw}}, 0), L)$$
3.  **Closed Loop ($\text{IsClosed}() = \text{true}, L > 0$)**: Euclidean modulo semantics apply to wrap negative and overflowing distances into $[0, L)$:
    $$s = d_{\text{raw}} - L \cdot \left\lfloor \frac{d_{\text{raw}}}{L} \right\rfloor \quad (\text{implemented via } \text{fmodf}(d_{\text{raw}}, L) \text{ adjusted for } < 0)$$

---

### 3. Transformation Matrix Derivation

In `ComputedStyle::ApplyMotionPathTransform(float origin_x, float origin_y, const gfx::RectF& bounding_box, ...)`:

Let $(origin_x, origin_y)$ be the anchor/transform-origin point of the element in its local coordinate system, and let $(O_x, O_y)$ be the resolved starting offset position (with `offset-anchor` resolved to $(A_x, A_y)$). Under standard default `offset-anchor: auto` and `offset-position: normal`, the reference point is the `transform-origin` $(origin_x, origin_y)$.

Let $(x(s), y(s))$ and $\theta(s)$ be the point and tangent angle at arc-length $s$. The effective rotation angle $\phi$ is:
$$\phi = \begin{cases} \theta(s) + \alpha & \text{if } \text{type} = \text{kAuto} \\ \alpha & \text{if } \text{type} = \text{kFixed} \end{cases}$$

Blink applies the operations to the transformation matrix $M$ in the following sequence (pre-multiplying column vectors):
1. Translate the element's reference point to the path point $(x(s), y(s))$ relative to the origin shift.
2. Rotate by $\phi$ around the anchor.

Specifically, in Blink's exact local-space composition around `origin_x, origin_y` (where $(x(s), y(s))$ is in the containing block's coordinate space and `origin` is the local anchor):
$$M = T(x(s), y(s)) \cdot R(\phi) \cdot T(-origin_x, -origin_y)$$
Expanding the $3 \times 3$ affine transformation matrix:
$$M = \begin{bmatrix} 1 & 0 & x(s) \\ 0 & 1 & y(s) \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} \cos\phi & -\sin\phi & 0 \\ \sin\phi & \cos\phi & 0 \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} 1 & 0 & -origin_x \\ 0 & 1 & -origin_y \\ 0 & 0 & 1 \end{bmatrix}$$

$$M = \begin{bmatrix} \cos\phi & -\sin\phi & x(s) - origin_x \cos\phi + origin_y \sin\phi \\ \sin\phi & \cos\phi & y(s) - origin_x \sin\phi - origin_y \cos\phi \\ 0 & 0 & 1 \end{bmatrix}$$

*(Verification: Applying $M$ to the local anchor $[origin_x, origin_y, 1]^T$ yields $[x(s), y(s), 1]^T$ regardless of $\phi$.)*

---

### 4. Mathematical Invariants

1.  **Arc-Length Containment**: For any total path length $L \ge 0$ and any `offset-distance` input, the resolved parameter $s$ satisfies $0 \le s \le L$.
2.  **Clamped Distance Monotonicity**: For an open path ($L \ge 0$) and purely percentage-based distances $p_1 \le p_2$, the resolved arc-lengths satisfy $s(p_1) \le s(p_2)$.
3.  **Anchor Fixed-Point Invariance**: Under transformation $M$, the local anchor point $(origin_x, origin_y)$ maps identically to $(x(s), y(s))$ for all rotation configurations $\phi \in \mathbb{R}$.
4.  **Rotation Additivity (Continuity)**: On $C^1$ smooth path segments where $\theta(s)$ is continuous, the effective rotation $\phi(s)$ is continuous and satisfies $R(\theta(s) + \alpha) = R(\theta(s)) \cdot R(\alpha)$.

---

### 5. Rocq / Coq Formalization (`BlinkMotionPathOffsetSemantics.v`)

```coq
(** * BlinkMotionPathOffsetSemantics.v
    Formal verification of Chromium Blink Motion Path (W3C Motion Path Level 1 §2) *)

From Coq Require Import Reals Lra.
Local Open Scope R_scope.

(** ** 1. Core Data Structures *)

Inductive LengthPercentage : Type :=
  | LP_Fixed (px : R)
  | LP_Percent (pct : R)
  | LP_Calc (px : R) (pct : R).

Inductive OffsetRotateType : Type :=
  | Rotate_Auto
  | Rotate_Fixed.

Record StyleOffsetRotation : Type := mkOffsetRotate {
  rot_type : OffsetRotateType;
  rot_angle : R (* in radians for trigonometric evaluation *)
}.

Record Point2D : Type := mkPoint2D {
  px : R;
  py : R
}.

Record PointAndTangent : Type := mkPointAndTangent {
  pt_pos : Point2D;
  pt_tangent : R (* in radians *)
}.

Record OffsetPath : Type := mkOffsetPath {
  path_length : R;
  path_is_closed : bool;
  path_eval : R -> PointAndTangent
}.

(** Affine 2D Transform Matrix:
    [ m11  m12  m13 ]
    [ m21  m22  m23 ]
    [  0    0    1  ] *)
Record AffineTransform : Type := mkAffine {
  m11 : R; m12 : R; m13 : R;
  m21 : R; m22 : R; m23 : R
}.

(** ** 2. Distance Along Path Resolution *)

Definition resolve_raw_distance (lp : LengthPercentage) (L : R) : R :=
  match lp with
  | LP_Fixed v => v
  | LP_Percent p => (p / 100) * L
  | LP_Calc v p => v + (p / 100) * L
  end.

Definition clamp (x low high : R) : R :=
  Rmin (Rmax x low) high.

(** Abstract floor function axiomatization for closed-path modulo *)
Parameter Rfloor : R -> R.
Axiom Rfloor_spec : forall x : R, Rfloor x <= x < Rfloor x + 1.

Definition rmod_positive (d L : R) : R :=
  d - L * Rfloor (d / L).

Definition resolve_arc_length (lp : LengthPercentage) (L : R) (is_closed : bool) : R :=
  if Rle_dec L 0 then 0
  else
    let d := resolve_raw_distance lp L in
    if is_closed then rmod_positive d L
    else clamp d 0 L.

(** ** 3. Transformation Matrix Derivation *)

Definition resolve_rotation (rot : StyleOffsetRotation) (tangent : R) : R :=
  match rot_type rot with
  | Rotate_Auto => tangent + rot_angle rot
  | Rotate_Fixed => rot_angle rot
  end.

Definition compute_motion_transform
  (pat : PointAndTangent) (rot : StyleOffsetRotation) (origin : Point2D) : AffineTransform :=
  let phi := resolve_rotation rot (pt_tangent pat) in
  let c := cos phi in
  let s := sin phi in
  let x := px (pt_pos pat) in
  let y := py (pt_pos pat) in
  let ox := px origin in
  let oy := py origin in
  mkAffine
    c (-s) (x - ox * c + oy * s)
    s   c  (y - ox * s - oy * c).

Definition apply_transform (M : AffineTransform) (p : Point2D) : Point2D :=
  mkPoint2D
    (m11 M * px p + m12 M * py p + m13 M)
    (m21 M * px p + m22 M * py p + m23 M).

(** ** 4. Mathematical Invariants & Theorems *)

Lemma clamp_bounds : forall x low high : R,
  low <= high -> low <= clamp x low high <= high.
Proof.
  intros x low high Hle. unfold clamp.
  split.
  - apply Rmin_glb; [apply Rmax_r | exact Hle].
  - apply Rmin_r.
Qed.

Lemma rmod_positive_bounds : forall d L : R,
  L > 0 -> 0 <= rmod_positive d L < L.
Proof.
  intros d L HL. unfold rmod_positive.
  pose proof (Rfloor_spec (d / L)) as [H1 H2].
  split.
  - apply Rmult_le_compat_r with (r := L) in H1; [| lra].
     unfold Rdiv in H1. rewrite Rmult_assoc in H1.
     rewrite Rinv_l in H1; lra.
  - apply Rmult_lt_compat_r with (r := L) in H2; [| lra].
    unfold Rdiv in H2. rewrite Rmult_plus_distr_r in H2.
    rewrite Rmult_assoc in H2. rewrite Rinv_l in H2; lra.
Qed.

(** Theorem 1: Arc-length parameter s is always contained in [0, L] for L >= 0 *)
Theorem arc_length_containment : forall (lp : LengthPercentage) (L : R) (closed : bool),
  0 <= L ->
  0 <= resolve_arc_length lp L closed <= L.
Proof.
  intros lp L closed HL. unfold resolve_arc_length.
  destruct (Rle_dec L 0) as [Hle | Hgt].
  - lra.
  - assert (HLpos : L > 0) by lra.
    destruct closed.
    + pose proof (rmod_positive_bounds (resolve_raw_distance lp L) L HLpos). lra.
    + apply clamp_bounds. lra.
Qed.

(** Theorem 2: Monotonicity of arc-length with respect to percentage progress on open paths *)
Theorem open_path_percentage_monotonic : forall (p1 p2 L : R),
  0 <= L ->
  p1 <= p2 ->
  resolve_arc_length (LP_Percent p1) L false <= resolve_arc_length (LP_Percent p2) L false.
Proof.
  intros p1 p2 L HL Hp. unfold resolve_arc_length.
  destruct (Rle_dec L 0); [lra |].
  unfold clamp, resolve_raw_distance.
  assert (Hd : (p1 / 100) * L <= (p2 / 100) * L).
  { apply Rmult_le_compat_r; lra. }
  apply Rmin_le_compat_r.
  apply Rmax_le_compat_r.
  exact Hd.
Qed.

(** Theorem 3: Anchor Fixed-Point Invariance
    Applying the derived motion transform to the local origin always yields the exact path point (x(s), y(s)). *)
Theorem motion_transform_maps_origin_to_path_point :
  forall (pat : PointAndTangent) (rot : StyleOffsetRotation) (origin : Point2D),
  apply_transform (