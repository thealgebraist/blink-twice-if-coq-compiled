### 1. Audit Summary: Chromium Blink `feComposite` Arithmetic Mode

In Chromium's Blink rendering engine (specifically within `FEComposite.cpp` and Skia's `SkArithmeticImageFilter`), the `feComposite` filter primitive in `arithmetic` mode computes each channel of the output pixel (in premultiplied alpha space) using the formula defined by the SVG 1.1 and Filter Effects Module Level 1 specifications:

$$\text{result} = k_1 \cdot \text{in}_1 \cdot \text{in}_2 + k_2 \cdot \text{in}_1 + k_3 \cdot \text{in}_2 + k_4$$

When implemented in integer/fixed-point arithmetic for 8-bit color channels ($\text{in}_1, \text{in}_2 \in [0, 255]$):
1. **Fixed-Point Coefficients:** The floating-point coefficients $k_1, k_2, k_3, k_4$ are scaled into fixed-point integers. Specifically, $k_1$ accounts for the $1/255$ normalization factor of the product $\text{in}_1 \cdot \text{in}_2$, while $k_2, k_3$ are scaled by $2^S$ (e.g., $S = 16$ or $S = 8$) and $k_4$ is scaled by $255 \cdot 2^S$.
2. **Saturation/Clamping:** The shifted result is clamped to the valid 8-bit unsigned integer range $[0, 255]$ to prevent integer overflow/underflow wrap-around artifacts when casting back to `uint8_t`.

---

### 2. Formal Verification in Rocq / Coq

Below is the complete, self-contained formalization `BlinkSVGCompositeArithmeticSemantics.v` using `ZArith` and `Lia`, containing zero `Admitted` statements.

```coq
(** * BlinkSVGCompositeArithmeticSemantics.v
    Formal Audit of Chromium Blink feComposite Arithmetic Mode
    Agent 293 - Fixed-Point Semantics & Clamping Invariants *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkArithmeticComposite.

  (** ** 1. Data Types and Clamping Semantics *)

  (** Clamps an arbitrary integer into the 8-bit channel domain [0, 255]. *)
  Definition clamp_u8 (x : Z) : Z :=
    Z.max 0 (Z.min 255 x).

  (** Predicate asserting a value is a valid 8-bit color channel. *)
  Definition is_u8 (x : Z) : Prop :=
    0 <= x <= 255.

  (** ** 2. Fixed-Point Arithmetic Composite Model *)

  (** In fixed-point implementations, coefficients k1..k4 are pre-scaled:
      - [k1_fp] is scaled by (2^shift / 255)
      - [k2_fp], [k3_fp] are scaled by (2^shift)
      - [k4_fp] is scaled by (255 * 2^shift)
      - [shift] is the fixed-point fractional bit width (e.g., 16).
      Division by (2^shift) models the arithmetic right shift (>> shift). *)

  Definition arith_composite_raw
    (k1_fp k2_fp k3_fp k4_fp : Z) (shift : Z) (i1 i2 : Z) : Z :=
    let acc := k1_fp * i1 * i2 + k2_fp * i1 + k3_fp * i2 + k4_fp in
    Z.shiftr acc shift.

  Definition arith_composite_pixel
    (k1_fp k2_fp k3_fp k4_fp : Z) (shift : Z) (i1 i2 : Z) : Z :=
    clamp_u8 (arith_composite_raw k1_fp k2_fp k3_fp k4_fp shift i1 i2).

  (** ** 3. Core Invariant Proofs *)

  (** Theorem 1: Clamp strictly bounds any integer within [0, 255]. *)
  Theorem clamp_u8_bounds : forall (x : Z),
    0 <= clamp_u8 x <= 255.
  Proof.
    intros x.
    unfold clamp_u8.
    lia.
  Qed.

  (** Theorem 2: Clamping is idempotent. *)
  Theorem clamp_u8_idempotent : forall (x : Z),
    clamp_u8 (clamp_u8 x) = clamp_u8 x.
  Proof.
    intros x.
    unfold clamp_u8.
    lia.
  Qed.

  (** Theorem 3: Values already in [0, 255] are invariant under clamping. *)
  Theorem clamp_u8_identity_on_u8 : forall (x : Z),
    is_u8 x -> clamp_u8 x = x.
  Proof.
    intros x H.
    unfold is_u8 in H.
    unfold clamp_u8.
    lia.
  Qed.

  (** Theorem 4: Clamping is monotonic. *)
  Theorem clamp_u8_monotonic : forall (x y : Z),
    x <= y -> clamp_u8 x <= clamp_u8 y.
  Proof.
    intros x y H.
    unfold clamp_u8.
    lia.
  Qed.

  (** Theorem 5: The arithmetic composite pixel evaluation is strictly within
      valid 8-bit bounds [0, 255] for all possible fixed-point coefficients,
      shifts, and input channel values. *)
  Theorem arith_composite_pixel_valid_u8 :
    forall (k1 k2 k3 k4 shift i1 i2 : Z),
      is_u8 (arith_composite_pixel k1 k2 k3 k4 shift i1 i2).
  Proof.
    intros k1 k2 k3 k4 shift i1 i2.
    unfold is_u8, arith_composite_pixel.
    apply clamp_u8_bounds.
  Qed.

  (** Theorem 6: Re-clamping the output of arith_composite_pixel is redundant. *)
  Theorem arith_composite_pixel_idempotent :
    forall (k1 k2 k3 k4 shift i1 i2 : Z),
      clamp_u8 (arith_composite_pixel k1 k2 k3 k4 shift i1 i2) =
      arith_composite_pixel k1 k2 k3 k4 shift i1 i2.
  Proof.
    intros k1 k2 k3 k4 shift i1 i2.
    unfold arith_composite_pixel.
    apply clamp_u8_idempotent.
  Qed.

  (** Theorem 7: Commutativity of inputs when k2 = k3. *)
  Theorem arith_composite_symmetric_when_k2_eq_k3 :
    forall (k1 k2 k4 shift i1 i2 : Z),
      arith_composite_pixel k1 k2 k2 k4 shift i1 i2 =
      arith_composite_pixel k1 k2 k2 k4 shift i2 i1.
  Proof.
    intros k1 k2 k4 shift i1 i2.
    unfold arith_composite_pixel, arith_composite_raw.
    f_equal.
    f_equal.
    lia.
  Qed.

  (** Theorem 8: Zero-input reduction (black/transparent pixel behavior).
      When both inputs are 0, output depends exclusively on k4 and shift. *)
  Theorem arith_composite_zero_inputs :
    forall (k1 k2 k3 k4 shift : Z),
      arith_composite_pixel k1 k2 k3 k4 shift 0 0 =
      clamp_u8 (Z.shiftr k4 shift).
  Proof.
    intros k1 k2 k3 k4 shift.
    unfold arith_composite_pixel, arith_composite_raw.
    f_equal.
    f_equal.
    lia.
  Qed.

End BlinkArithmeticComposite.
```