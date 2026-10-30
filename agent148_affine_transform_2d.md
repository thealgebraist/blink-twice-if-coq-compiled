### 1. Representation of 2D AffineTransform Matrix

In Chromium Blink (`third_party/blink/renderer/platform/transforms/affine_transform.h`), a 2D affine transformation is represented by 6 double-precision floating-point values: $a, b, c, d, e, f$.

Per CSS Transforms Module Level 1 (§5 & §6), this 6-tuple corresponds to the $3 \times 3$ homogeneous transformation matrix:

$$
M = \begin{bmatrix} 
a & c & e \\ 
b & d & f \\ 
0 & 0 & 1 
\end{bmatrix}
$$

When transforming a 2D column vector $P = [x, y, 1]^T$, the resulting point $P' = [x', y', 1]^T$ is computed as $P' = M \cdot P$:
*   $x' = a \cdot x + c \cdot y + e$
*   $y' = b \cdot x + d \cdot y + f$

---

### 2. Matrix Composition (Multiplication)

In Blink, `AffineTransform::Multiply(const AffineTransform& other)` (or `t1 * t2`) post-multiplies the current matrix $T_1$ by $T_2$ ($T_{out} = T_1 \times T_2$). 

Given $T_1 = [a_1, b_1, c_1, d_1, e_1, f_1]$ and $T_2 = [a_2, b_2, c_2, d_2, e_2, f_2]$:

$$
\begin{bmatrix} 
a_1 & c_1 & e_1 \\ 
b_1 & d_1 & f_1 \\ 
0 & 0 & 1 
\end{bmatrix}
\times
\begin{bmatrix} 
a_2 & c_2 & e_2 \\ 
b_2 & d_2 & f_2 \\ 
0 & 0 & 1 
\end{bmatrix}
=
\begin{bmatrix} 
a_1 a_2 + c_1 b_2 & a_1 c_2 + c_1 d_2 & a_1 e_2 + c_1 f_2 + e_1 \\ 
b_1 a_2 + d_1 b_2 & b_1 c_2 + d_1 d_2 & b_1 e_2 + d_1 f_2 + f_1 \\ 
0 & 0 & 1 
\end{bmatrix}
$$

Component-wise definition of $T_{out} = [a', b', c', d', e', f']$:
*   $a' = a_1 a_2 + c_1 b_2$
*   $b' = b_1 a_2 + d_1 b_2$
*   $c' = a_1 c_2 + c_1 d_2$
*   $d' = b_1 c_2 + d_1 d_2$
*   $e' = a_1 e_2 + c_1 f_2 + e_1$
*   $f' = b_1 e_2 + d_1 f_2 + f_1$

---

### 3. Core Audit Invariants

Under idealized real arithmetic ($\mathbb{R}$, abstracting IEEE-754 rounding errors):
1.  **Identity Neutrality:** $I = [1, 0, 0, 1, 0, 0]$ satisfies $\forall T, I \times T = T \land T \times I = T$.
2.  **Composition Associativity:** $\forall T_1, T_2, T_3, (T_1 \times T_2) \times T_3 = T_1 \times (T_2 \times T_3)$.
3.  **Scaling Linearity (Multiplicativity):** `Scale(sx1, sy1) * Scale(sx2, sy2) = Scale(sx1 * sx2, sy1 * sy2)`.
4.  **Translation Offset Addition:** `Translate(tx1, ty1) * Translate(tx2, ty2) = Translate(tx1 + tx2, ty1 + ty2)`.
5.  **Point Mapping Homomorphism:** $\text{Map}(T_1 \times T_2, P) = \text{Map}(T_1, \text{Map}(T_2, P))$.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkAffineTransform2DSemantics.v`)

```coq
(** * BlinkAffineTransform2DSemantics.v
    Agent 148 Audit: Chromium Blink 2D Affine Transform Composition
    vs CSS Transforms Module Level 1 (§5, §6). *)

From Coq Require Import Reals.
From Coq Require Import Lra.
Open Scope R_scope.

(** 1. Representation of 2D AffineTransform: [a, b, c, d, e, f]
    Matrix layout:
    | a c e |
    | b d f |
    | 0 0 1 | *)
Record AffineTransform : Type := mkAffine {
  a : R;
  b : R;
  c : R;
  d : R;
  e : R;
  f : R
}.

(** 2D Point representation *)
Record Point2D : Type := mkPoint {
  px : R;
  py : R
}.

(** Standard Generators *)
Definition Identity : AffineTransform :=
  mkAffine 1 0 0 1 0 0.

Definition Translation (tx ty : R) : AffineTransform :=
  mkAffine 1 0 0 1 tx ty.

Definition Scaling (sx sy : R) : AffineTransform :=
  mkAffine sx 0 0 sy 0 0.

(** 2. Matrix Composition: Multiply (t1 * t2) *)
Definition multiply (t1 t2 : AffineTransform) : AffineTransform :=
  mkAffine
    (t1.(a) * t2.(a) + t1.(c) * t2.(b))
    (t1.(b) * t2.(a) + t1.(d) * t2.(b))
    (t1.(a) * t2.(c) + t1.(c) * t2.(d))
    (t1.(b) * t2.(c) + t1.(d) * t2.(d))
    (t1.(a) * t2.(e) + t1.(c) * t2.(f) + t1.(e))
    (t1.(b) * t2.(e) + t1.(d) * t2.(f) + t1.(f)).

(** Point Transformation: MapPoint *)
Definition map_point (t : AffineTransform) (p : Point2D) : Point2D :=
  mkPoint
    (t.(a) * p.(px) + t.(c) * p.(py) + t.(e))
    (t.(b) * p.(px) + t.(d) * p.(py) + t.(f)).

(** Helper lemma for structural equality of AffineTransform *)
Lemma affine_eq : forall t1 t2 : AffineTransform,
  t1.(a) = t2.(a) -> t1.(b) = t2.(b) ->
  t1.(c) = t2.(c) -> t1.(d) = t2.(d) ->
  t1.(e) = t2.(e) -> t1.(f) = t2.(f) ->
  t1 = t2.
Proof.
  intros [a1 b1 c1 d1 e1 f1] [a2 b2 c2 d2 e2 f2]; simpl; intros; subst; reflexivity.
Qed.

(** 3. Invariant Proofs *)

(** Invariant 3.1a: Left Identity Neutrality *)
Theorem multiply_identity_left : forall t : AffineTransform,
  multiply Identity t = t.
Proof.
  intros t. apply affine_eq; simpl; lra.
Qed.

(** Invariant 3.1b: Right Identity Neutrality *)
Theorem multiply_identity_right : forall t : AffineTransform,
  multiply t Identity = t.
Proof.
  intros t. apply affine_eq; simpl; lra.
Qed.

(** Invariant 3.2: Associativity of Transform Composition *)
Theorem multiply_assoc : forall t1 t2 t3 : AffineTransform,
  multiply (multiply t1 t2) t3 = multiply t1 (multiply t2 t3).
Proof.
  intros t1 t2 t3. apply affine_eq; simpl; lra.
Qed.

(** Invariant 3.3: Scaling Linearity (Multiplicativity) *)
Theorem scaling_composition : forall sx1 sy1 sx2 sy2 : R,
  multiply (Scaling sx1 sy1) (Scaling sx2 sy2) = Scaling (sx1 * sx2) (sy1 * sy2).
Proof.
  intros. apply affine_eq; simpl; lra.
Qed.

(** Invariant 3.4: Translation Offset Addition *)
Theorem translation_composition : forall tx1 ty1 tx2 ty2 : R,
  multiply (Translation tx1 ty1) (Translation tx2 ty2) = Translation (tx1 + tx2) (ty1 + ty2).
Proof.
  intros. apply affine_eq; simpl; lra.
Qed.

(** Invariant 3.5: Point Mapping Homomorphism *)
Theorem map_point_composition : forall (t1 t2 : AffineTransform) (p : Point2D),
  map_point (multiply t1 t2) p = map_point t1 (map_point t2 p).
Proof.
  intros [a1 b1 c1 d1 e1 f1] [a2 b2 c2 d2 e2 f2] [x y].
  unfold map_point, multiply; simpl.
  f_equal; lra.
Qed.
```