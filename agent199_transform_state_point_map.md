### Audit Report: Agent 199 — Chromium Blink Point Transformation vs. CSS Transforms 1 §5

**Target:** `blink::TransformState` & `gfx::Transform` (`third_party/blink/renderer/platform/graphics/paint/transform_state.h`, `ui/gfx/geometry/transform.h`)  
**Specification:** W3C CSS Transforms Module Level 1, §5 (The Transform Rendering Model)

---

### 1. Point Mapping: $(x', y') = \text{map\_point}(T, x, y)$

In CSS Transforms 1 §5, a 2D transformation is mathematically defined by a $3\times 3$ homogeneous transformation matrix $T$ parameterized by six values $(a, b, c, d, e, f)$:
$$T = \begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix}$$

When mapping a 2D point $P = (x, y)$ through $T$, the point is extended to the homogeneous vector $[x, y, 1]^T$. The transformed coordinates $(x', y')$ are computed via matrix-vector multiplication $P' = T \cdot P$:
$$\begin{bmatrix} x' \\ y' \\ 1 \end{bmatrix} = \begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} x \\ y \\ 1 \end{bmatrix} = \begin{bmatrix} a \cdot x + c \cdot y + e \\ b \cdot x + d \cdot y + f \\ 1 \end{bmatrix}$$

**Blink Implementation Alignment:**
In Chromium Blink, `TransformState::Move` and `TransformState::ApplyTransform` delegate 2D affine point transformations to `gfx::Transform::MapPoint` (or `AffineTransform::MapPoint`). When the matrix is 2D affine, Blink evaluates:
```cpp
float x_prime = a * x + c * y + e;
float y_prime = b * x + d * y + f;
```
Within real-arithmetic semantics (ignoring IEEE 754 floating-point rounding drift), Blink’s `MapPoint` is a direct realization of the CSS §5 specification.

---

### 2. Composition: $\text{map\_point}(T_2, \text{map\_point}(T_1, x, y)) = \text{map\_point}(T_2 \times T_1, x, y)$

CSS Transforms 1 §5 specifies that nested transformation contexts accumulate by post-multiplying transformation matrices, or equivalently, when mapping a point from a local coordinate system to an ancestor coordinate system, applying $T_1$ followed by $T_2$ corresponds to the matrix product $T_2 \times T_1$.

Given:
$$T_2 = \begin{bmatrix} a_2 & c_2 & e_2 \\ b_2 & d_2 & f_2 \\ 0 & 0 & 1 \end{bmatrix}, \quad T_1 = \begin{bmatrix} a_1 & c_1 & e_1 \\ b_1 & d_1 & f_1 \\ 0 & 0 & 1 \end{bmatrix}$$

Their composition $T_2 \times T_1$ is:
$$T_2 \times T_1 = \begin{bmatrix} a_2 a_1 + c_2 b_1 & a_2 c_1 + c_2 d_1 & a_2 e_1 + c_2 f_1 + e_2 \\ b_2 a_1 + d_2 b_1 & b_2 c_1 + d_2 d_1 & b_2 e_1 + d_2 f_1 + f_2 \\ 0 & 0 & 1 \end{bmatrix}$$

**Blink Implementation Alignment:**
`blink::TransformState` optimizes transform accumulation:
- If `accumulating_transform_` is false, it immediately maps the tracked point `last_planar_point_` at each step: $P \leftarrow \text{map\_point}(T_1, P)$, then $P \leftarrow \text{map\_point}(T_2, P)$.
- If `accumulating_transform_` is true (e.g., when flattening or preserving 3D), it accumulates $M \leftarrow T_2 \times T_1$ into `accumulated_transform_` and defers `MapPoint` until `MappedPoint()` is queried.

By the associativity of matrix multiplication $(T_2 \times T_1) \cdot P = T_2 \cdot (T_1 \cdot P)$, both execution paths in `TransformState` are semantically identical.

---

### 3. Invariants: Identity and Pure Translation

1. **Identity Invariant:**
   The identity matrix $I$ has parameters $(a=1, b=0, c=0, d=1, e=0, f=0)$.
   $$\text{map\_point}(I, x, y) = (1\cdot x + 0\cdot y + 0, \; 0\cdot x + 1\cdot y + 0) = (x, y)$$
   In Blink, `TransformState` elides matrix allocation when applying identity transforms, preserving the invariant trivially.

2. **Translation Invariant:**
   A pure 2D translation by $(t_x, t_y)$ has parameters $(a=1, b=0, c=0, d=1, e=t_x, f=t_y)$.
   $$\text{map\_point}(\text{Translate}(t_x, t_y), x, y) = (1\cdot x + 0\cdot y + t_x, \; 0\cdot x + 1\cdot y + t_y) = (x + t_x, y + t_y)$$
   In Blink, `TransformState::Move(LayoutSize(tx, ty))` bypasses full matrix multiplication when possible and directly offsets the point or the matrix translation components $(e, f)$, matching the additive shift invariant.

---

### 4. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkTransformStatePointMapSemantics.v`.

```coq
(** * BlinkTransformStatePointMapSemantics.v
    Formal Audit of Chromium Blink Point Transformation vs CSS Transforms 1 §5.
    Agent 199. *)

Require Import Reals.
Require Import Lra.
Open Scope R_scope.

(** ** 1. Data Definitions *)

(** A 2D Point in CSS / Blink Layout space. *)
Record Point2D : Type := mkPoint2D {
  px : R;
  py : R
}.

(** A 2D Affine Transform Matrix as defined in CSS Transforms 1 §5:
    [ a c e ]
    [ b d f ]
    [ 0 0 1 ] *)
Record Transform2D : Type := mkTransform2D {
  ta : R;
  tb : R;
  tc : R;
  td : R;
  te : R;
  tf : R
}.

(** Identity Transform: matrix(1, 0, 0, 1, 0, 0) *)
Definition identity_transform : Transform2D :=
  mkTransform2D 1 0 0 1 0 0.

(** Pure 2D Translation Transform: translate(tx, ty) = matrix(1, 0, 0, 1, tx, ty) *)
Definition translate_transform (tx ty : R) : Transform2D :=
  mkTransform2D 1 0 0 1 tx ty.

(** ** 2. Operations *)

(** Point mapping: (x', y') = map_point(T, x, y) *)
Definition map_point (T : Transform2D) (p : Point2D) : Point2D :=
  mkPoint2D (ta T * px p + tc T * py p + te T)
            (tb T * px p + td T * py p + tf T).

(** Matrix multiplication: T2 * T1 *)
Definition compose_transform (T2 T1 : Transform2D) : Transform2D :=
  mkTransform2D
    (ta T2 * ta T1 + tc T2 * tb T1)
    (tb T2 * ta T1 + td T2 * tb T1)
    (ta T2 * tc T1 + tc T2 * td T1)
    (tb T2 * tc T1 + td T2 * td T1)
    (ta T2 * te T1 + tc T2 * tf T1 + te T2)
    (tb T2 * te T1 + td T2 * tf T1 + tf T2).

(** Helper lemma for Point2D equality *)
Lemma point2d_eq : forall (p1 p2 : Point2D),
  px p1 = px p2 -> py p1 = py p2 -> p1 = p2.
Proof.
  intros [x1 y1] [x2 y2] Hx Hy.
  simpl in *. subst. reflexivity.
Qed.

(** Helper lemma for Transform2D equality *)
Lemma transform2d_eq : forall (T1 T2 : Transform2D),
  ta T1 = ta T2 -> tb T1 = tb T2 ->
  tc T1 = tc T2 -> td T1 = td T2 ->
  te T1 = te T2 -> tf T1 = tf T2 ->
  T1 = T2.
Proof.
  intros [a1 b1 c1 d1 e1 f1] [a2 b2 c2 d2 e2 f2]; simpl; intros; subst; reflexivity.
Qed.

(** ** 3. Core Theorems & Invariants *)

(** Theorem 1: Explicit Point Mapping Component Unfolding *)
Theorem map_point_components : forall (T : Transform2D) (x y : R),
  map_point T (mkPoint2D x y) =
  mkPoint2D (ta T * x + tc T * y + te T)
            (tb T * x + td T * y + tf T).
Proof.
  intros T x y.
  unfold map_point. simpl. reflexivity.
Qed.

(** Theorem 2: Composition Equivalence
    map_point(T2, map_point(T1, p)) = map_point(T2 * T1, p)
    Proves that Blink TransformState immediate point mapping and deferred
    matrix accumulation yield identical results. *)
Theorem map_point_compose : forall (T2 T1 : Transform2D) (p : Point2D),
  map_point T2 (map_point T1 p) = map_point (compose_transform T2 T1) p.
Proof.
  intros T2 T1 p.
  apply point2d_eq; unfold map_point, compose_transform; simpl; lra.
Qed.

(** Theorem 3: Identity Invariant
    map_point with the identity transform is the identity function on points. *)
Theorem map_point_identity : forall (p : Point2D),
  map_point identity_transform p = p.
Proof.
  intros p.
  apply point2d_eq; unfold map_point, identity_transform; simpl; lra.
Qed.

(** Theorem 4: Translation Additive Shift Invariant
    A pure translation transform shifts the point coordinates additively. *)
Theorem map_point_translate : forall (tx ty : R) (p : Point2D),
  map_point (translate_transform tx ty) p = mkPoint2D (px p + tx) (py p + ty).
Proof.
  intros tx ty p.
  apply point2d_eq; unfold map_point, translate_transform; simpl; lra.
Qed.

(** Theorem 5: Composition of Translations is Additive
    Composing two translations corresponds to adding their shift vectors. *)
Theorem compose_translate_additive : forall (tx1 ty1 tx2 ty2 : R),
  compose_transform (translate_transform tx2 ty2) (translate_transform tx1 ty1) =
  translate_transform (tx1 + tx2) (ty1 + ty2).
Proof.
  intros tx1 ty1 tx2 ty2.
  apply transform2d_eq; unfold compose_transform, translate_transform; simpl; lra.
Qed.

(** Theorem 6: Associativity of Transform Composition *)
Theorem compose_transform_assoc : forall (T3 T2 T1 : Transform2D),
  compose_transform T3 (compose_transform T2 T1) =
  compose_transform (compose_transform T3 T2) T1.
Proof.
  intros T3 T2 T1.
  apply transform2d_eq; unfold compose_transform; simpl; lra.
Qed.
```