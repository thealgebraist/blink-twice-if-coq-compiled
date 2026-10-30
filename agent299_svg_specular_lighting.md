### 1. Specular Lighting Intensity Calculation (Phong Model)

In the Chromium Blink rendering engine (specifically within `third_party/blink/renderer/platform/graphics/filters/fe_specular_lighting.cc` and its Skia counterpart `SkLightingImageFilter`), the `feSpecularLighting` SVG filter primitive calculates the specular reflection of a light source using a modified Blinn-Phong reflectance model.

For a given pixel on the height map defined by the input alpha channel:
1. **Surface Normal ($\vec{N}$):** Calculated from the 3x3 Sobel gradient of the input alpha channel and normalized to unit length.
2. **Light Vector ($\vec{L}$):** Unit vector pointing from the surface point to the light source (distant, point, or spot).
3. **Halfway Vector ($\vec{H}$):** Unit vector halfway between the light vector $\vec{L}$ and the fixed eye/view vector $\vec{E} = (0, 0, 1)$:
   $$\vec{H} = \frac{\vec{L} + \vec{E}}{\|\vec{L} + \vec{E}\|}$$
4. **Non-Negative Dot Product:** The cosine of the angle between the normal and the halfway vector is computed. To prevent negative intensity values when the light is behind the surface, this dot product is clamped at zero:
   $$d = \max(0, \vec{N} \cdot \vec{H})$$
5. **Exponentiation & Intensity:** The specular reflection factor is computed by raising the clamped dot product to the power of the `specularExponent` ($e$, referred to as shininess in standard Phong lighting) and scaling by the `specularConstant` ($k_s \ge 0$) and the light source color intensity ($I_L \in [0, 255]$):
   $$I_{\text{raw}} = k_s \cdot I_L \cdot (\max(0, \vec{N} \cdot \vec{H}))^e$$

---

### 2. Core Invariants

During the execution of the pixel shader / rasterization pipeline for `feSpecularLighting`, the following invariants must hold:

1. **Non-Negativity of Specular Factor:** Because the base of the exponentiation $\max(0, \vec{N} \cdot \vec{H})$ is strictly non-negative, the resulting specular factor $d^e$ is guaranteed to be non-negative ($\ge 0$), avoiding complex number domains (NaNs in IEEE-754 `powf`) and negative color channels.
2. **8-Bit Channel Clamping:** The final computed intensity for each RGB channel (and the resulting alpha channel, which in `feSpecularLighting` is defined as $\max(R, G, B)$) is strictly clamped to the 8-bit unsigned integer range $[0, 255]$ before being written to the output pixel buffer:
   $$I_{\text{out}} = \min(255, \max(0, \lfloor I_{\text{raw}} \rfloor))$$

---

### 3. Concrete Rocq / Coq Formalization

Below is the self-contained formalization in Coq (`BlinkSVGSpecularLightingSemantics.v`). It models the computation over exact integers (`Z`) to mirror discrete pixel bounds and fixed-point/clamped representations without any admitted lemmas (`0 admits`).

```coq
(** * BlinkSVGSpecularLightingSemantics.v
    Formal audit of Chromium Blink feSpecularLighting (Blinn-Phong Model). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Mathematical Primitives & Clamping *)

(** Clamps an integer value into the [low, high] range. *)
Definition clamp (val low high : Z) : Z :=
  Z.min high (Z.max low val).

(** Clamps a color channel intensity into the standard 8-bit [0, 255] range. *)
Definition clamp_channel (val : Z) : Z :=
  clamp val 0 255.

(** Clamps a dot product to be non-negative: max(0, N . H). *)
Definition non_neg_dot (dot_nh : Z) : Z :=
  Z.max 0 dot_nh.

(** ** 2. Specular Lighting Model Definitions *)

(** Computes the unscaled specular factor: (max(0, N . H)) ^ exponent. *)
Definition specular_factor (dot_nh exponent : Z) : Z :=
  Z.pow (non_neg_dot dot_nh) exponent.

(** Computes the raw specular intensity before 8-bit clamping:
    I_raw = k_s * light_color * (max(0, N . H) ^ exponent). *)
Definition raw_specular_intensity (ks light_color dot_nh exponent : Z) : Z :=
  ks * light_color * (specular_factor dot_nh exponent).

(** Computes the final 8-bit pixel channel output for feSpecularLighting. *)
Definition fe_specular_lighting_channel (ks light_color dot_nh exponent : Z) : Z :=
  clamp_channel (raw_specular_intensity ks light_color dot_nh exponent).

(** Computes the alpha channel of feSpecularLighting, which the SVG spec
    defines as the maximum of the clamped R, G, B channels. *)
Definition fe_specular_lighting_alpha (r g b : Z) : Z :=
  Z.max r (Z.max g b).

(** ** 3. Security & Correctness Theorems (0 Admits) *)

(** Lemma: The clamped dot product is always non-negative. *)
Lemma non_neg_dot_ge_0 : forall (dot_nh : Z),
  0 <= non_neg_dot dot_nh.
Proof.
  intros dot_nh.
  unfold non_neg_dot.
  lia.
Qed.

(** Theorem 1: The exponentiated specular factor is strictly non-negative
    for all inputs. *)
Theorem specular_factor_non_negative : forall (dot_nh exponent : Z),
  0 <= specular_factor dot_nh exponent.
Proof.
  intros dot_nh exponent.
  unfold specular_factor.
  destruct (Z_lt_ge_dec exponent 0) as [Hneg | Hpos].
  - (* Case: exponent < 0 -> Z.pow returns 0 by definition in Coq *)
    rewrite Z.pow_neg_r by exact Hneg.
    lia.
  - (* Case: exponent >= 0 -> base >= 0 implies base^exp >= 0 *)
    apply Z.pow_nonneg.
    apply non_neg_dot_ge_0.
Qed.

(** Theorem 2: If the physical parameters (ks and light_color) are non-negative,
    the raw specular intensity never underflows below 0. *)
Theorem raw_intensity_non_negative : forall (ks light_color dot_nh exponent : Z),
  0 <= ks ->
  0 <= light_color ->
  0 <= raw_specular_intensity ks light_color dot_nh exponent.
Proof.
  intros ks light_color dot_nh exponent Hks Hlight.
  unfold raw_specular_intensity.
  apply Z.mul_nonneg_nonneg.
  - apply Z.mul_nonneg_nonneg; assumption.
  - apply specular_factor_non_negative.
Qed.

(** Lemma: Generic clamp guarantees bounds when low <= high. *)
Lemma clamp_bounds : forall (val low high : Z),
  low <= high ->
  low <= clamp val low high <= high.
Proof.
  intros val low high Hle.
  unfold clamp.
  lia.
Qed.

(** Theorem 3 (Primary Invariant): The output intensity of feSpecularLighting
    is strictly bounded within [0, 255] for any arbitrary inputs. *)
Theorem fe_specular_lighting_channel_bounds :
  forall (ks light_color dot_nh exponent : Z),
  0 <= fe_specular_lighting_channel ks light_color dot_nh exponent <= 255.
Proof.
  intros ks light_color dot_nh exponent.
  unfold fe_specular_lighting_channel, clamp_channel.
  apply clamp_bounds.
  lia.
Qed.

(** Theorem 4: When physical parameters are non-negative, the lower bound
    clamp (max 0) is redundant because raw intensity is already >= 0. *)
Theorem fe_specular_lighting_lower_clamp_redundant :
  forall (ks light_color dot_nh exponent : Z),
  0 <= ks ->
  0 <= light_color ->
  fe_specular_lighting_channel ks light_color dot_nh exponent =
  Z.min 255 (raw_specular_intensity ks light_color dot_nh exponent).
Proof.
  intros ks light_color dot_nh exponent Hks Hlight.
  unfold fe_specular_lighting_channel, clamp_channel, clamp.
  pose proof (raw_intensity_non_negative ks light_color dot_nh exponent Hks Hlight) as Hraw.
  rewrite Z.max_r by exact Hraw.
  reflexivity.
Qed.

(** Theorem 5: The derived alpha channel preserves the [0, 255] invariant
    if the RGB channels satisfy the [0, 255] invariant. *)
Theorem fe_specular_lighting_alpha_bounds :
  forall (r g b : Z),
  0 <= r <= 255 ->
  0 <= g <= 255 ->
  0 <= b <= 255 ->
  0 <= fe_specular_lighting_alpha r g b <= 255.
Proof.
  intros r g b Hr Hg Hb.
  unfold fe_specular_lighting_alpha.
  lia.
Qed.
```