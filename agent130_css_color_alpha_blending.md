Here is the architectural specification and formal verification artifact for Agent 130's audit of Chromium Blink CSS Color & Alpha Blending against the W3C CSS Color Module Level 4 (§12) specification.

### 1. RGBA Color Channel Clamping to $[0, 255]$
In Chromium Blink (specifically within `third_party/blink/renderer/platform/graphics/color.h` and Skia's `SkColor` primitives), legacy sRGB color channels and alpha values are represented as 8-bit unsigned integers (`uint8_t`), mapping the normalized floating-point domain $[0.0, 1.0]$ to the discrete integer interval $[0, 255]$. 

When parsing out-of-gamut CSS specifications (e.g., `rgb(300, -10, 128)`), CSS Color 4 §12 dictates that channel values must be clamped to the boundary limits of the target color space prior to serialization or compositing. Formally, for any unbounded integer channel calculation $x \in \mathbb{Z}$, the clamping projection $\text{clamp}_{255} : \mathbb{Z} \to [0, 255]$ is defined piecewise as:
$$\text{clamp}_{255}(x) = \min(\max(x, 0), 255)$$

### 2. Source-Over Alpha Compositing
Under CSS Color 4 §12 and the Porter-Duff `source-over` compositing operator, blending a foreground source channel $C_{\text{src}} \in [0, 255]$ with an alpha value $\alpha \in [0, 255]$ over an opaque destination channel $C_{\text{dst}} \in [0, 255]$ is governed by the linear interpolation equation:
$$C_{\text{out}} = \left\lfloor \frac{\alpha \cdot C_{\text{src}} + (255 - \alpha) \cdot C_{\text{dst}}}{255} \right\rfloor$$

*(Note: While hardware-accelerated paths in Blink/Skia often use rounding by adding $127$ or $128$ prior to bit-shifting approximations like `(x + (x >> 8) + 0x80) >> 8`, the baseline integer division specification analyzed here forms the exact mathematical floor bound).*

### 3. Core Invariants
1. **Channel Bounds Preservation:** For all valid inputs $\alpha, C_{\text{src}}, C_{\text{dst}} \in [0, 255]$, the resulting blended channel $C_{\text{out}}$ is strictly bounded within $[0, 255]$ without requiring post-compositing clamping.
2. **Opacity Monotonicity:** If the source channel is brighter than or equal to the destination channel ($C_{\text{src}} \ge C_{\text{dst}}$), increasing the source opacity ($\alpha_1 \le \alpha_2$) monotonically increases (or keeps constant) the resulting blended channel value: $C_{\text{out}}(\alpha_1) \le C_{\text{out}}(\alpha_2)$.
3. **Boundary Identity:** 
   - **Full Opacity ($\alpha = 255$):** The destination channel is completely occluded, yielding $C_{\text{out}} = C_{\text{src}}$.
   - **Full Transparency ($\alpha = 0$):** The source channel vanishes completely, yielding $C_{\text{out}} = C_{\text{dst}}$.

---

### 4. Formal Verification in Rocq / Coq (`BlinkCSSColorAlphaBlendingSemantics.v`)

Below is the complete, self-contained, and constructive Coq script formalizing the clamping semantics, the compositing operator, and machine-checked proofs for all required invariants.

```coq
(** * BlinkCSSColorAlphaBlendingSemantics.v
    Agent 130 Audit: Chromium Blink CSS Color & Alpha Blending vs CSS Color 4 §12.
    Formalization of 8-bit RGBA channel clamping and source-over alpha compositing. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. RGBA Color Channel Clamping to [0, 255] *)

Definition valid_channel (c : Z) : Prop :=
  0 <= c <= 255.

Definition clamp_255 (x : Z) : Z :=
  Z.min (Z.max x 0) 255.

(** Theorem: The clamping operator strictly maps any integer into [0, 255]. *)
Theorem clamp_255_in_bounds : forall (x : Z),
  valid_channel (clamp_255 x).
Proof.
  intros x.
  unfold valid_channel, clamp_255.
  lia.
Qed.

(** Theorem: Clamping is idempotent on already valid channels. *)
Theorem clamp_255_idempotent : forall (c : Z),
  valid_channel c -> clamp_255 c = c.
Proof.
  intros c H.
  unfold valid_channel in H.
  unfold clamp_255.
  lia.
Qed.

(** ** 2. Source-Over Alpha Compositing *)

(** Computes C = (alpha * C_src + (255 - alpha) * C_dst) / 255 *)
Definition blend_channel (alpha c_src c_dst : Z) : Z :=
  (alpha * c_src + (255 - alpha) * c_dst) / 255.

(** Record representing an RGBA color in Blink's 8-bit per channel layout. *)
Record RGBA := mkRGBA {
  r_chan : Z;
  g_chan : Z;
  b_chan : Z;
  a_chan : Z
}.

Definition valid_rgba (color : RGBA) : Prop :=
  valid_channel (r_chan color) /\
  valid_channel (g_chan color) /\
  valid_channel (b_chan color) /\
  valid_channel (a_chan color).

(** ** 3. Core Invariant Proofs *)

(** *** Invariant 3.1: Blended Channel Remains in [0, 255] *)
Theorem blend_channel_bounds : forall (alpha c_src c_dst : Z),
  valid_channel alpha ->
  valid_channel c_src ->
  valid_channel c_dst ->
  valid_channel (blend_channel alpha c_src c_dst).
Proof.
  intros alpha c_src c_dst Halpha Hsrc Hdst.
  unfold valid_channel in *.
  unfold blend_channel.
  split.
  - (* Lower bound: 0 <= (alpha * c_src + (255 - alpha) * c_dst) / 255 *)
    apply Z.div_pos; nia.
  - (* Upper bound: (alpha * c_src + (255 - alpha) * c_dst) / 255 <= 255 *)
    apply Z.div_le_upper_bound; nia.
Qed.

(** *** Invariant 3.2: Opacity Monotonicity *)
(** Helper Lemma: Division by a positive integer preserves monotonicity. *)
Lemma Z_div_le_mono : forall (a b c : Z),
  0 < c -> a <= b -> a / c <= b / c.
Proof.
  intros a b c Hc Hab.
  apply Z.div_le_mono; assumption.
Qed.

(** When C_src >= C_dst, increasing alpha monotonically increases the blended result. *)
Theorem blend_opacity_monotonic : forall (alpha1 alpha2 c_src c_dst : Z),
  valid_channel alpha1 ->
  valid_channel alpha2 ->
  valid_channel c_src ->
  valid_channel c_dst ->
  c_dst <= c_src ->
  alpha1 <= alpha2 ->
  blend_channel alpha1 c_src c_dst <= blend_channel alpha2 c_src c_dst.
Proof.
  intros alpha1 alpha2 c_src c_dst Ha1 Ha2 Hsrc Hdst Hcmp Hle.
  unfold valid_channel in *.
  unfold blend_channel.
  apply Z_div_le_mono.
  - lia.
  - (* Algebraically: alpha1 * c_src + (255 - alpha1) * c_dst <= alpha2 * c_src + (255 - alpha2) * c_dst
       Rewrites to: (alpha2 - alpha1) * (c_src - c_dst) >= 0 *)
    nia.
Qed.

(** Dual Monotonicity: When C_src <= C_dst, increasing alpha monotonically decreases the result. *)
Theorem blend_opacity_antitonic : forall (alpha1 alpha2 c_src c_dst : Z),
  valid_channel alpha1 ->
  valid_channel alpha2 ->
  valid_channel c_src ->
  valid_channel c_dst ->
  c_src <= c_dst ->
  alpha1 <= alpha2 ->
  blend_channel alpha2 c_src c_dst <= blend_channel alpha1 c_src c_dst.
Proof.
  intros alpha1 alpha2 c_src c_dst Ha1 Ha2 Hsrc Hdst Hcmp Hle.
  unfold valid_channel in *.
  unfold blend_channel.
  apply Z_div_le_mono; nia.
Qed.

(** *** Invariant 3.3: Boundary Identities *)

(** Boundary Identity 1: alpha = 255 yields C_src exactly. *)
Theorem blend_alpha_255_identity : forall (c_src c_dst : Z),
  blend_channel 255 c_src c_dst = c_src.
Proof.
  intros c_src c_dst.
  unfold blend_channel.
  replace (255 * c_src + (255 - 255) * c_dst) with (c_src * 255) by lia.
  apply Z.div_mul.
  lia.
Qed.

(** Boundary Identity 2: alpha = 0 yields C_dst exactly. *)
Theorem blend_alpha_0_identity : forall (c_src c_dst : Z),
  blend_channel 0 c_src c_dst = c_dst.
Proof.
  intros c_src c_dst.
  unfold blend_channel.
  replace (0 * c_src + (255 - 0) * c_dst) with (c_dst * 255) by lia.
  apply Z.div_mul.
  lia.
Qed.

(** Additional Invariant: Blending identical channels is invariant to alpha. *)
Theorem blend_idempotent_channel : forall (alpha c : Z),
  blend_channel alpha c c = c.
Proof.
  intros alpha c.
  unfold blend_channel.
  replace (alpha * c + (255 - alpha) * c) with (c * 255) by lia.
  apply Z.div_mul.
  lia.
Qed.
```