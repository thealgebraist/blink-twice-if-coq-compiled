## 1. Specification & Chromium Alignment

### CSS Transforms Module Level 1 §5.1 (2D Transform Functions)
A 2D rotation `rotate(<angle>)` specifies a 2D rotation by the angle $\alpha$ about the origin of the element (as defined by the `transform-origin` property). It is equivalent to the 2D matrix $[a, b, c, d, e, f]$:
$$\begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix} = \begin{bmatrix} \cos(\alpha) & -\sin(\alpha) & 0 \\ \sin(\alpha) & \cos(\alpha) & 0 \\ 0 & 0 & 1 \end{bmatrix}$$
In linear 6-tuple notation `[a, b, c, d, e, f]`, this is represented as:
`[cos(α), sin(α), -sin(α), cos(α), 0, 0]`.

The determinant of the linear transformation part is:
$$\det(M) = a \cdot d - b \cdot c = \cos(\alpha)\cos(\alpha) - \sin(\alpha)(-\sin(\alpha)) = \cos^2(\alpha) + \sin^2(\alpha) = 1$$

### Chromium Blink Implementation (`gfx::Transform` / `AffineTransform`)
In Chromium (`third_party/blink/renderer/platform/transforms/affine_transform.cc`), `AffineTransform::Rotate(double d)` converts degrees to radians and applies the rotation matrix:
```cpp
AffineTransform& AffineTransform::RotateRadians(double radians) {
  double cos_angle = std::cos(radians);
  double sin_angle = std::sin(radians);
  AffineTransform rot(cos_angle, sin_angle, -sin_angle, cos_angle, 0, 0);
  Multiply(rot);
  return *this;
}
```
This matches the CSS specification exactly.

---

## 2. Core Mathematical Invariants

1. **Unit Determinant (Area Preservation & Invertibility):** For all real angles $\alpha \in \mathbb{R}$, the determinant of the 2D rotation matrix equals $1$. Consequently, a pure 2D rotation is never singular and preserves 2D area and orientation.
2. **Zero Rotation Identity:** Rotating by $0$ radians yields the exact 2D identity matrix `[1, 0, 0, 1, 0, 0]`.
3. **Additive Homomorphism (Composition):** Rotating by $\alpha$ and then by $\beta$ is equivalent to a single rotation by $\alpha + \beta$.
4. **Orthogonality / Inverse:** The inverse of a rotation by $\alpha$ is a rotation by $-\alpha$.

---

## 3. Rocq / Coq Formalization (`BlinkTransformRotation2DSemantics.v`)

Below is the complete, self-contained formalization of the 2D rotation semantics and its invariants using the standard Rocq real number library (`Reals`).

```coq
(** * BlinkTransformRotation2DSemantics.v
    Formal audit of Chromium Blink 2D Rotation Matrix vs CSS Transforms 1 §5.1.
    Agent 204. *)

From Coq Require Import Reals.
From Coq Require Import Lra.
Open Scope R_scope.

(** ** 1. 2D Affine Matrix Representation *)

(** CSS Transforms 1 §5.1 represents a 2D matrix as a 6-tuple [a, b, c, d, e, f]
    corresponding to the homogeneous matrix:
    | a  c  e |
    | b  d  f |
    | 0  0  1 | *)
Record Matrix2D : Type := mkMatrix2D {
  m_a : R;
  m_b : R;
  m_c : R;
  m_d : R;
  m_e : R;
  m_f : R
}.

(** The 2D Identity Matrix: [1, 0, 0, 1, 0, 0] *)
Definition identity_2d : Matrix2D :=
  mkMatrix2D 1 0 0 1 0 0.

(** Matrix multiplication for 2D affine transforms *)
Definition multiply_2d (m1 m2 : Matrix2D) : Matrix2D :=
  mkMatrix2D
    (m_a m1 * m_a m2 + m_c m1 * m_b m2)
    (m_b m1 * m_a m2 + m_d m1 * m_b m2)
    (m_a m1 * m_c m2 + m_c m1 * m_d m2)
    (m_b m1 * m_c m2 + m_d m1 * m_d m2)
    (m_a m1 * m_e m2 + m_c m1 * m_f m2 + m_e m1)
    (m_b m1 * m_e m2 + m_d m1 * m_f m2 + m_f m1).

(** Determinant of the 2D affine matrix *)
Definition det_2d (m : Matrix2D) : R :=
  m_a m * m_d m - m_b m * m_c m.

(** ** 2. 2D Rotation Matrix Definition (CSS Transforms 1 §5.1) *)

(** [cos(alpha), sin(alpha), -sin(alpha), cos(alpha), 0, 0] *)
Definition rotate_2d (alpha : R) : Matrix2D :=
  mkMatrix2D (cos alpha) (sin alpha) (- sin alpha) (cos alpha) 0 0.

(** ** 3. Formal Invariants and Theorems *)

(** Invariant 1: The determinant of any 2D rotation matrix is 1 (Area Preservation). *)
Theorem rotate_2d_det_is_one : forall (alpha : R),
  det_2d (rotate_2d alpha) = 1.
Proof.
  intros alpha.
  unfold det_2d, rotate_2d; simpl.
  replace (cos alpha * cos alpha - sin alpha * - sin alpha)
     with (Rsqr (sin alpha) + Rsqr (cos alpha))
       by (unfold Rsqr; ring).
  apply sin2_cos2.
Qed.

(** Corollary: A 2D rotation matrix is always invertible (non-singular). *)
Corollary rotate_2d_non_singular : forall (alpha : R),
  det_2d (rotate_2d alpha) <> 0.
Proof.
  intros alpha.
  rewrite rotate_2d_det_is_one.
  lra.
Qed.

(** Invariant 2: Rotation by 0 radians is the exact 2D identity matrix. *)
Theorem rotate_2d_zero_is_identity :
  rotate_2d 0 = identity_2d.
Proof.
  unfold rotate_2d, identity_2d.
  rewrite cos_0, sin_0.
  f_equal; lra.
Qed.

(** Invariant 3: Composition of two 2D rotations is additive in angle. *)
Theorem rotate_2d_composition : forall (alpha beta : R),
  multiply_2d (rotate_2d alpha) (rotate_2d beta) = rotate_2d (alpha + beta).
Proof.
  intros alpha beta.
  unfold multiply_2d, rotate_2d; simpl.
  f_equal.
  - (* m_a: cos(a+b) = cos(a)cos(b) - sin(a)sin(b) *)
    rewrite cos_plus. ring.
  - (* m_b: sin(a+b) = sin(a)cos(b) + cos(a)sin(b) *)
    rewrite sin_plus. ring.
  - (* m_c: -sin(a+b) *)
    rewrite sin_plus. ring.
  - (* m_d: cos(a+b) *)
    rewrite cos_plus. ring.
  - (* m_e: translation X remains 0 *)
    ring.
  - (* m_f: translation Y remains 0 *)
    ring.
Qed.

(** Invariant 4: Rotating by -alpha is the exact inverse of rotating by alpha. *)
Theorem rotate_2d_inverse : forall (alpha : R),
  multiply_2d (rotate_2d alpha) (rotate_2d (- alpha)) = identity_2d.
Proof.
  intros alpha.
  rewrite rotate_2d_composition.
  replace (alpha + - alpha) with 0 by ring.
  apply rotate_2d_zero_is_identity.
Qed.

(** Invariant 5: Origin preservation (0,0 maps to 0,0). *)
Definition apply_point_2d (m : Matrix2D) (x y : R) : R * R :=
  (m_a m * x + m_c m * y + m_e m,
   m_b m * x + m_d m * y + m_f m).

Theorem rotate_2d_preserves_origin : forall (alpha : R),
  apply_point_2d (rotate_2d alpha) 0 0 = (0, 0).
Proof.
  intros alpha.
  unfold apply_point_2d, rotate_2d; simpl.
  f_equal; ring.
Qed.

(** Invariant 6: Euclidean distance from origin (norm squared) is preserved. *)
Theorem rotate_2d_preserves_norm_sq : forall (alpha x y : R),
  let (x', y') := apply_point_2d (rotate_2d alpha) x y in
  x' * x' + y' * y' = x * x + y * y.
Proof.
  intros alpha x y.
  unfold apply_point_2d, rotate_2d; simpl.
  replace ((cos alpha * x + - sin alpha * y + 0) * (cos alpha * x + - sin alpha * y + 0) +
           (sin alpha * x + cos alpha * y + 0) * (sin alpha * x + cos alpha * y + 0))
     with ((Rsqr (sin alpha) + Rsqr (cos alpha)) * (x * x + y * y))
       by (unfold Rsqr; ring).
  rewrite sin2_cos2.
  ring.
Qed.
```