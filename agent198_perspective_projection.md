### 1. Audit Summary: Chromium Blink vs. CSS Transforms Level 2 §4

#### CSS Transforms Level 2 §4 Specification
According to **CSS Transforms Module Level 2 §4 (Perspective)** and **§12 (Mathematical Description of Transform Functions)**, the perspective matrix $P(d)$ for a given perspective depth $d > 0$ is defined as a 4x4 homogeneous matrix where element $m_{34} = -1/d$:

$$P(d) = \begin{bmatrix} 1 & 0 & 0 & 0 \\ 0 & 1 & 0 & 0 \\ 0 & 0 & 1 & 0 \\ 0 & 0 & -1/d & 1 \end{bmatrix}$$

When transforming a 3D point $(x, y, z, 1)^T$, the resulting homogeneous coordinate vector is:

$$P(d) \cdot \begin{bmatrix} x \\ y \\ z \\ 1 \end{bmatrix} = \begin{bmatrix} x \\ y \\ z \\ 1 - \frac{z}{d} \end{bmatrix} = \begin{bmatrix} x \\ y \\ z \\ \frac{d - z}{d} \end{bmatrix}$$

To project this point into 2D screen space (the $z=0$ plane), homogeneous division by $w = \frac{d - z}{d}$ is performed. For all points strictly behind the camera eye plane ($z < d$, meaning $w > 0$), the projected coordinates $(x', y')$ are scaled by the **perspective scale factor** $\text{scale}(d, z)$:

$$\text{scale}(d, z) = \frac{1}{w} = \frac{d}{d - z} \quad \text{for } z < d$$

#### Chromium Blink Implementation Audit
In Chromium Blink (specifically within `third_party/blink/renderer/platform/transforms/transformation_matrix.cc` and `ui/gfx/geometry/transform.cc`), `ApplyPerspectiveDepth(double d)` mutates the matrix by applying $m_{34} = -1.0 / d$. During point projection (`MapPoint` / `ProjectPoint`), Blink computes `w = x * m_14 + y * m_24 + z * m_34 + m_44`. For a pure perspective transform, this evaluates to `w = 1.0 - z / d`.

* **Conformance:** Blink checks `if (w <= 0)` to handle clipping/clamping near or behind the camera plane ($z \ge d$). In the non-singular, visible half-space ($z < d$), Blink scales $(x, y)$ by `1.0 / w`, which algebraically matches $\frac{d}{d - z}$ up to IEEE-754 floating-point rounding.

---

### 2. Mathematical Invariants

For a valid CSS perspective distance $d > 0$ and $z \in (-\infty, d)$:

1. **Well-Definedness & Positivity:** Since $z < d$, the denominator $d - z > 0$. Combined with $d > 0$, the scale factor is strictly positive: $\text{scale}(d, z) > 0$.
2. **Neutrality at the $z=0$ Plane:** Objects resting directly on the rendering plane ($z = 0$) undergo no perspective scaling:
   $$\text{scale}(d, 0) = \frac{d}{d - 0} = 1$$
3. **Strict Monotonicity:** As an object moves closer to the viewer ($z_1 < z_2 < d$), its apparent size strictly increases:
   $$z_1 < z_2 < d \implies 0 < d - z_2 < d - z_1 \implies \frac{d}{d - z_1} < \frac{d}{d - z_2}$$
4. **Depth Partitioning:**
   * **Magnification ($0 < z < d$):** Objects in front of the $z=0$ plane appear larger than their intrinsic size ($\text{scale}(d, z) > 1$).
   * **Minification ($z < 0$):** Objects behind the $z=0$ plane appear smaller than their intrinsic size ($0 < \text{scale}(d, z) < 1$).

---

### 3. Rocq / Coq Formalization (`BlinkPerspectiveProjectionSemantics.v`)

The following file is completely self-contained and compiles cleanly under standard Coq/Rocq (8.16+ / 8.18+ / 8.19+) with zero `Admitted` obligations.

```coq
(** * BlinkPerspectiveProjectionSemantics.v
    Formal Audit of Chromium Blink Perspective Projection vs CSS Transforms 2 §4.
    Agent 198 - Perspective Scale Factor & Monotonicity Verification. *)

From Coq Require Import Reals Lra.
Open Scope R_scope.

Section PerspectiveProjection.

  (** ** 1. Definitions *)

  (** [perspective_scale d z] computes the homogeneous projection scale factor
      1/w = d / (d - z) for a perspective matrix with depth [d] at coordinate [z]. *)
  Definition perspective_scale (d z : R) : R :=
    d / (d - z).

  (** [project_1d d x z] projects a 1D coordinate [x] at depth [z] onto the z=0 plane
      given perspective depth [d]. *)
  Definition project_1d (d x z : R) : R :=
    x * perspective_scale d z.

  (** Homogeneous w-coordinate produced by Blink's TransformationMatrix::MapPoint
      for a pure perspective matrix where m34 = -1/d. *)
  Definition blink_homogeneous_w (d z : R) : R :=
    1 - z / d.

  (** ** 2. Equivalence Between Blink's 1/w and CSS d/(d-z) *)

  Theorem blink_w_positive :
    forall d z : R,
      d > 0 ->
      z < d ->
      blink_homogeneous_w d z > 0.
  Proof.
    intros d z Hd Hz.
    unfold blink_homogeneous_w.
    assert (Hdz : d - z > 0) by lra.
    replace (1 - z / d) with ((d - z) / d) by (field; lra).
    apply Rdiv_lt_0_compat; lra.
  Qed.

  Theorem blink_reciprocal_w_eq_perspective_scale :
    forall d z : R,
      d > 0 ->
      z < d ->
      1 / blink_homogeneous_w d z = perspective_scale d z.
  Proof.
    intros d z Hd Hz.
    unfold blink_homogeneous_w, perspective_scale.
    field.
    split; lra.
  Qed.

  (** ** 3. Core Invariants *)

  (** Invariant 0: The denominator is non-zero and the scale factor is strictly
      positive across the entire visible domain (z < d). *)
  Theorem perspective_scale_pos :
    forall d z : R,
      d > 0 ->
      z < d ->
      perspective_scale d z > 0.
  Proof.
    intros d z Hd Hz.
    unfold perspective_scale.
    apply Rdiv_lt_0_compat; lra.
  Qed.

  (** Invariant 1: Neutrality at z = 0.
      Points on the z=0 plane are unaffected by perspective projection. *)
  Theorem perspective_scale_zero_neutral :
    forall d : R,
      d > 0 ->
      perspective_scale d 0 = 1.
  Proof.
    intros d Hd.
    unfold perspective_scale.
    field; lra.
  Qed.

  Corollary project_1d_zero_neutral :
    forall d x : R,
      d > 0 ->
      project_1d d x 0 = x.
  Proof.
    intros d x Hd.
    unfold project_1d.
    rewrite perspective_scale_zero_neutral by assumption.
    lra.
  Qed.

  (** Algebraic difference identity used to prove strict monotonicity:
      scale(d, z2) - scale(d, z1) = d * (z2 - z1) / ((d - z1) * (d - z2)). *)
  Lemma perspective_scale_diff_identity :
    forall d z1 z2 : R,
      z1 < d ->
      z2 < d ->
      perspective_scale d z2 - perspective_scale d z1 =
        (d * (z2 - z1)) / ((d - z1) * (d - z2)).
  Proof.
    intros d z1 z2 Hz1 Hz2.
    unfold perspective_scale.
    field.
    split; lra.
  Qed.

  (** Invariant 2: Strict monotonicity in z for z < d.
      As z approaches the viewer plane d, the scale factor strictly increases. *)
  Theorem perspective_scale_strictly_monotonic :
    forall d z1 z2 : R,
      d > 0 ->
      z1 < z2 ->
      z2 < d ->
      perspective_scale d z1 < perspective_scale d z2.
  Proof.
    intros d z1 z2 Hd Hz12 Hz2d.
    assert (Hz1d : z1 < d) by lra.
    apply Rminus_gt_0_lt.
    rewrite perspective_scale_diff_identity by assumption.
    apply Rdiv_lt_0_compat.
    - apply Rmult_lt_0_compat; lra.
    - apply Rmult_lt_0_compat; lra.
  Qed.

  (** ** 4. Depth Partitioning Invariants *)

  (** Objects in front of the z=0 plane (0 < z < d) are magnified (scale > 1). *)
  Theorem perspective_scale_magnifies_positive_z :
    forall d z : R,
      d > 0 ->
      0 < z ->
      z < d ->
      perspective_scale d z > 1.
  Proof.
    intros d z Hd Hz0 Hzd.
    rewrite <- (perspective_scale_zero_neutral d Hd).
    apply perspective_scale_strictly_monotonic; lra.
  Qed.

  (** Objects behind the z=0 plane (z < 0) are minified (0 < scale < 1). *)
  Theorem perspective_scale_minifies_negative_z :
    forall d z : R,
      d > 0 ->
      z < 0 ->
      0 < perspective_scale d z < 1.
  Proof.
    intros d z Hd Hz0.
    split.
    - apply perspective_scale_pos; lra.
    - rewrite <- (perspective_scale_zero_neutral d Hd).
      apply perspective_scale_strictly_monotonic; lra.
  Qed.

End PerspectiveProjection.
```