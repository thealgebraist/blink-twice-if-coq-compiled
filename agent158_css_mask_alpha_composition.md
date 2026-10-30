### 1. Alpha Mask Application in `MaskPainter` (`core/paint/mask_painter.cc`)

In Chromium Blink’s rendering pipeline, CSS masking (as specified in CSS Masking Module Level 1, §3 & §4) is orchestrated during the paint phase by `MaskPainter` (and its successor logic within `BoxFragmentPainter` / `PaintLayerPainter` in LayoutNG). 

When an element has a `mask-image` or `-webkit-mask-box-image` applied with `mask-mode: alpha` (or when compositing the computed mask layer), Blink isolates the element's painted output and intersects it with the mask's alpha channel:

1. **Source Layer Isolation (`kSrcOver`):** Blink begins a compositing layer for the masked element using `GraphicsContext::BeginLayer`. The element's background, borders, and children are painted into this intermediate buffer, producing pixels with source premultiplied color and alpha $A_{\text{src}} \in [0, 255]$.
2. **Mask Layer Blending (`SkBlendMode::kDstIn`):** `MaskPainter` opens a nested compositing layer specifically configured with the Porter-Duff `DstIn` blend mode (`cc::PaintFlags::setBlendMode(SkBlendMode::kDstIn)`).
3. **Mask Painting & Alpha Extraction:** The mask images are painted into this `kDstIn` layer. When `mask-mode` resolves to `alpha` (the default for `mask-image` references to raster/gradient images), the rasterizer extracts the 8-bit alpha channel $A_{\text{mask}} \in [0, 255]$ of the mask image directly. (If `mask-mode: luminance` is used, a color filter first converts RGB luminance into the alpha channel before `kDstIn` compositing).
4. **Layer Restoration:** Upon `GraphicsContext::EndLayer()`, Skia composites the `kDstIn` mask buffer over the isolated element buffer, scaling both the source alpha and premultiplied RGB components by the mask's alpha fraction.

---

### 2. Alpha Multiplication Mechanics

In 8-bit unsigned integer color space ($\mathbb{Z} \cap [0, 255]$), normalized alpha values $\alpha \in [0.0, 1.0]$ are represented as integers $A = \lfloor 255 \cdot \alpha \rfloor$. 

Under CSS Masking 1 §3 & §4 and the Porter-Duff `DstIn` compositing operator, the continuous output alpha is $\alpha_{\text{out}} = \alpha_{\text{src}} \cdot \alpha_{\text{mask}}$. In discrete 8-bit arithmetic, exact division by $255$ defines the canonical integer quantization:

$$A_{\text{out}} = \left\lfloor \frac{A_{\text{src}} \cdot A_{\text{mask}}}{255} \right\rfloor$$

*(Note: In hardware/SIMD paths inside Skia, this is frequently approximated via the fast bit-shift identity $((A_{\text{src}} \cdot A_{\text{mask}} + 128) \cdot 257) \gg 16$ or $(A_{\text{src}} \cdot (A_{\text{mask}} + (A_{\text{mask}} \gg 7))) \gg 8$, which coincides with exact division or rounded division while strictly preserving the boundary invariants).*

---

### 3. Formal Invariants

For all $A_{\text{src}}, A_{\text{mask}} \in [0, 255]$:

1. **Range Boundedness:** Because $A_{\text{src}} \ge 0$ and $A_{\text{mask}} \ge 0$, their product is non-negative, ensuring $A_{\text{out}} \ge 0$. Because $A_{\text{src}} \le 255$ and $A_{\text{mask}} \le 255$, $A_{\text{src}} \cdot A_{\text{mask}} \le 255 \cdot 255$. Dividing by $255$ yields $A_{\text{out}} \le 255$.
2. **Zero Mask Annihilation (Full Clip):** When $A_{\text{mask}} = 0$, $A_{\text{out}} = \lfloor (A_{\text{src}} \cdot 0) / 255 \rfloor = 0$. The masked element is completely transparent regardless of $A_{\text{src}}$.
3. **Opaque Mask Identity (Full Pass):** When $A_{\text{mask}} = 255$, $A_{\text{out}} = \lfloor (A_{\text{src}} \cdot 255) / 255 \rfloor = A_{\text{src}}$. The element retains its exact original opacity.
4. **Bimonotonicity:** Since multiplication on non-negative integers and integer division by a positive constant ($255$) are both order-preserving operations, increasing either $A_{\text{src}}$ or $A_{\text{mask}}$ cannot decrease $A_{\text{out}}$.

---

### 4. Rocq / Coq Formalization (`BlinkCSSMaskAlphaCompositionSemantics.v`)

The following file is completely self-contained and compiles cleanly in Coq/Rocq without any admits.

```coq
(** * BlinkCSSMaskAlphaCompositionSemantics.v
    Formal audit of Chromium Blink CSS Mask Alpha Composition
    against CSS Masking Module Level 1 (§3 & §4). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Definitions *)

(** Valid 8-bit alpha channel domain: [0, 255] *)
Definition is_byte (a : Z) : Prop :=
  0 <= a <= 255.

(** Canonical 8-bit alpha mask composition (Porter-Duff DstIn alpha):
    A_out = (A_src * A_mask) / 255 *)
Definition compose_mask_alpha (a_src a_mask : Z) : Z :=
  (a_src * a_mask) / 255.

(** ** 2. Structural & Algebraic Properties *)

(** Symmetry / Commutativity of alpha multiplication *)
Theorem compose_mask_alpha_comm :
  forall a_src a_mask : Z,
    compose_mask_alpha a_src a_mask = compose_mask_alpha a_mask a_src.
Proof.
  intros a_src a_mask.
  unfold compose_mask_alpha.
  rewrite Z.mul_comm.
  reflexivity.
Qed.

(** ** 3. Core Audit Invariants *)

(** Invariant 1: Output alpha is bounded in [0, 255] whenever inputs are in [0, 255]. *)
Theorem compose_mask_alpha_bounded :
  forall a_src a_mask : Z,
    is_byte a_src ->
    is_byte a_mask ->
    is_byte (compose_mask_alpha a_src a_mask).
Proof.
  intros a_src a_mask [Hsrc_lo Hsrc_hi] [Hmask_lo Hmask_hi].
  unfold is_byte, compose_mask_alpha.
  split.
  - apply Z.div_pos.
    + lia.
    + lia.
  - apply Z.div_le_upper_bound.
    + lia.
    + nia.
Qed.

(** Invariant 2a: Full Clip (A_mask = 0 gives A_out = 0). *)
Theorem compose_mask_alpha_zero_mask :
  forall a_src : Z,
    compose_mask_alpha a_src 0 = 0.
Proof.
  intros a_src.
  unfold compose_mask_alpha.
  rewrite Z.mul_0_r.
  rewrite Z.div_0_l; [reflexivity | lia].
Qed.

(** Invariant 2b: Empty Source (A_src = 0 gives A_out = 0). *)
Theorem compose_mask_alpha_zero_src :
  forall a_mask : Z,
    compose_mask_alpha 0 a_mask = 0.
Proof.
  intros a_mask.
  rewrite compose_mask_alpha_comm.
  apply compose_mask_alpha_zero_mask.
Qed.

(** Invariant 3a: Full Pass (A_mask = 255 gives A_out = A_src). *)
Theorem compose_mask_alpha_full_mask :
  forall a_src : Z,
    compose_mask_alpha a_src 255 = a_src.
Proof.
  intros a_src.
  unfold compose_mask_alpha.
  apply Z.div_mul.
  lia.
Qed.

(** Invariant 3b: Opaque Source (A_src = 255 gives A_out = A_mask). *)
Theorem compose_mask_alpha_full_src :
  forall a_mask : Z,
    compose_mask_alpha 255 a_mask = a_mask.
Proof.
  intros a_mask.
  rewrite compose_mask_alpha_comm.
  apply compose_mask_alpha_full_mask.
Qed.

(** Invariant 4a: Monotonicity in Source Alpha. *)
Theorem compose_mask_alpha_mono_src :
  forall a_src1 a_src2 a_mask : Z,
    0 <= a_mask ->
    a_src1 <= a_src2 ->
    compose_mask_alpha a_src1 a_mask <= compose_mask_alpha a_src2 a_mask.
Proof.
  intros a_src1 a_src2 a_mask Hmask Hle.
  unfold compose_mask_alpha.
  apply Z.div_le_mono.
  - lia.
  - apply Z.mul_le_mono_nonneg_r; lia.
Qed.

(** Invariant 4b: Monotonicity in Mask Alpha. *)
Theorem compose_mask_alpha_mono_mask :
  forall a_src a_mask1 a_mask2 : Z,
    0 <= a_src ->
    a_mask1 <= a_mask2 ->
    compose_mask_alpha a_src a_mask1 <= compose_mask_alpha a_src a_mask2.
Proof.
  intros a_src a_mask1 a_mask2 Hsrc Hle.
  rewrite (compose_mask_alpha_comm a_src a_mask1).
  rewrite (compose_mask_alpha_comm a_src a_mask2).
  apply compose_mask_alpha_mono_src; assumption.
Qed.

(** Invariant 4c: Joint Monotonicity in both Source and Mask Alphas. *)
Theorem compose_mask_alpha_mono_joint :
  forall a_src1 a_src2 a_mask1 a_mask2 : Z,
    0 <= a_src1 ->
    0 <= a_mask1 ->
    a_src1 <= a_src2 ->
    a_mask1 <= a_mask2 ->
    compose_mask_alpha a_src1 a_mask1 <= compose_mask_alpha a_src2 a_mask2.
Proof.
  intros a_src1 a_src2 a_mask1 a_mask2 Hsrc1 Hmask1 Hle_src Hle_mask.
  apply Z.le_trans with (m := compose_mask_alpha a_src2 a_mask1).
  - apply compose_mask_alpha_mono_src; lia.
  - apply compose_mask_alpha_mono_mask; lia.
Qed.

(** Invariant 5: Attenuation property (Masking never amplifies source alpha). *)
Theorem compose_mask_alpha_attenuates_src :
  forall a_src a_mask : Z,
    is_byte a_src ->
    is_byte a_mask ->
    compose_mask_alpha a_src a_mask <= a_src.
Proof.
  intros a_src a_mask [Hsrc_lo Hsrc_hi] [Hmask_lo Hmask_hi].
  rewrite <- (compose_mask_alpha_full_mask a_src) at 2.
  apply compose_mask_alpha_mono_mask; lia.
Qed.
```