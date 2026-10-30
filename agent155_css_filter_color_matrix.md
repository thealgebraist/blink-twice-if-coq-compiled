### 1. Filter Matrix Builder in `FilterEffectBuilder` and `fe_color_matrix.cc`

In Chromium Blink (`third_party/blink/renderer/core/paint/filter_effect_builder.cc` and `third_party/blink/renderer/core/svg/graphics/filters/svg_fe_color_matrix.cc`), CSS shorthand filter functions (`brightness()`, `contrast()`, `grayscale()`, `sepia()`, `saturate()`, `hue-rotate()`, `invert()`, `opacity()`) are lowered into SVG filter primitives, predominantly `FEColorMatrix` (backed by Skia's `SkColorFilters::Matrix`).

Per **Filter Effects Module Level 1 §5 (Filter Function Lists)** and **§13 (`feColorMatrix` element)**:
* **`FilterEffectBuilder::BuildFilterEffect`**: Iterates over `FilterOperations`. For color-manipulating operations, it constructs a $5 \times 4$ (20-element) row-major color matrix operating on premultiplied or unpremultiplied RGBA color vectors $[R, G, B, A, 1]^T$.
* **`fe_color_matrix.cc` (`FEColorMatrix::CreateFilter`)**: Translates SVG `type="matrix" | "saturate" | "hueRotate" | "luminanceToAlpha"` into the 20-element float array passed to `cc::PaintFilter` / `SkColorFilter`. In Skia's normalized space $[0, 1]$, the translation column (5th column) is scaled by $1/255$ (or $255$ when operating directly on 8-bit integer channels $[0, 255]$).

The transformation on an input pixel $(R, G, B, A) \in [0, 255]^4$ is defined by:
$$
\begin{bmatrix} R' \\ G' \\ B' \\ A' \end{bmatrix} = \text{clamp}_{[0, 255]} \left( \begin{bmatrix}
m_{0} & m_{1} & m_{2} & m_{3} & m_{4} \\
m_{5} & m_{6} & m_{7} & m_{8} & m_{9} \\
m_{10} & m_{11} & m_{12} & m_{13} & m_{14} \\
m_{15} & m_{16} & m_{17} & m_{18} & m_{19}
\end{bmatrix} \begin{bmatrix} R \\ G \\ B \\ A \\ 1 \end{bmatrix} \right)
$$

---

### 2. Channel Scaling & Clamping Semantics

When operating over integer 8-bit color channels $c \in [0, 255]$ (with parameters scaled to fixed-point or integer arithmetic):

1. **`brightness(b)`**:
   Per Filter Effects 1 §5.1 / §13, `brightness(b)` applies a linear multiplier $b \ge 0$ to the $R, G, B$ channels with zero offset:
   $$M_{\text{brightness}}(b) = \begin{bmatrix} b & 0 & 0 & 0 & 0 \\ 0 & b & 0 & 0 & 0 \\ 0 & 0 & b & 0 & 0 \\ 0 & 0 & 0 & 1 & 0 \end{bmatrix}$$
   Each color channel $x \in \{R, G, B\}$ maps to $\text{clamp}_{[0, 255]}(b \cdot x)$.

2. **`contrast(c)`**:
   Per Filter Effects 1 §5.1, `contrast(c)` scales the $R, G, B$ channels by $c$ around the midpoint $0.5$ (which is $128$ in $[0, 255]$ integer space, or $127.5$ in exact float):
   $$M_{\text{contrast}}(c) = \begin{bmatrix} c & 0 & 0 & 0 & 128(1 - c) \\ 0 & c & 0 & 0 & 128(1 - c) \\ 0 & 0 & c & 0 & 128(1 - c) \\ 0 & 0 & 0 & 1 & 0 \end{bmatrix}$$
   Each color channel $x \in \{R, G, B\}$ maps to $\text{clamp}_{[0, 255]}(c \cdot (x - 128) + 128)$.

3. **Channel Output Clamping**:
   At the end of the color matrix evaluation stage, each resulting channel value $v$ is clamped to the displayable 8-bit integer range $[0, 255]$:
   $$\text{clamp}_{[0, 255]}(v) = \min(255, \max(0, v))$$

---

### 3. Core Invariants

1. **Identity of `brightness(1)`**: For any valid input channel $x \in [0, 255]$, applying `brightness(1)` yields $x$ unchanged ($\text{brightness}(1, x) = x$). Similarly, `contrast(1)` is an identity operation ($\text{contrast}(1, x) = x$).
2. **Output Channel Boundedness**: For any arbitrary filter parameters $b, c \in \mathbb{Z}$ and any input channel $x \in \mathbb{Z}$, the output of the filter channel pipeline is strictly bounded within $[0, 255]$.
3. **Monotonicity of `brightness(b)`**: For any non-negative input channel $x \ge 0$ and brightness multipliers $b_1 \le b_2$, $\text{brightness}(b_1, x) \le \text{brightness}(b_2, x)$.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkCSSFilterColorMatrixSemantics.v`)

```coq
(** * BlinkCSSFilterColorMatrixSemantics.v
    Formal audit of Chromium Blink CSS Filter Color Matrix (FilterEffectBuilder /
    fe_color_matrix.cc) against W3C Filter Effects Module Level 1 §5 & §13. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Channel Clamping and Color Primitives *)

Definition clamp_channel (v : Z) : Z :=
  Z.min 255 (Z.max 0 v).

Record RGBA : Type := mkRGBA {
  r_chan : Z;
  g_chan : Z;
  b_chan : Z;
  a_chan : Z
}.

Definition valid_channel (x : Z) : Prop :=
  0 <= x <= 255.

Definition valid_rgba (p : RGBA) : Prop :=
  valid_channel (r_chan p) /\
  valid_channel (g_chan p) /\
  valid_channel (b_chan p) /\
  valid_channel (a_chan p).

(** ** 2. Filter Channel Operations (Brightness & Contrast) *)

(** [brightness_channel b x] scales channel [x] by multiplier [b] and clamps to [0, 255]. *)
Definition brightness_channel (b x : Z) : Z :=
  clamp_channel (b * x).

(** [contrast_channel c x] scales channel [x] around midpoint 128 by [c] and clamps to [0, 255]. *)
Definition contrast_channel (c x : Z) : Z :=
  clamp_channel (c * (x - 128) + 128).

Definition apply_brightness (b : Z) (p : RGBA) : RGBA :=
  mkRGBA
    (brightness_channel b (r_chan p))
    (brightness_channel b (g_chan p))
    (brightness_channel b (b_chan p))
    (clamp_channel (a_chan p)).

Definition apply_contrast (c : Z) (p : RGBA) : RGBA :=
  mkRGBA
    (contrast_channel c (r_chan p))
    (contrast_channel c (g_chan p))
    (contrast_channel c (b_chan p))
    (clamp_channel (a_chan p)).

(** ** 3. General 5x4 Color Matrix Evaluation *)

Record ColorMatrixRow : Type := mkRow {
  m_r : Z;
  m_g : Z;
  m_b : Z;
  m_a : Z;
  m_offset : Z
}.

Definition eval_row (row : ColorMatrixRow) (p : RGBA) : Z :=
  clamp_channel (
    (m_r row) * (r_chan p) +
    (m_g row) * (g_chan p) +
    (m_b row) * (b_chan p) +
    (m_a row) * (a_chan p) +
    (m_offset row)
  ).

Record ColorMatrix5x4 : Type := mkMatrix {
  row_r : ColorMatrixRow;
  row_g : ColorMatrixRow;
  row_b : ColorMatrixRow;
  row_a : ColorMatrixRow
}.

Definition eval_color_matrix (m : ColorMatrix5x4) (p : RGBA) : RGBA :=
  mkRGBA
    (eval_row (row_r m) p)
    (eval_row (row_g m) p)
    (eval_row (row_b m) p)
    (eval_row (row_a m) p).

Definition brightness_matrix (b : Z) : ColorMatrix5x4 :=
  mkMatrix
    (mkRow b 0 0 0 0)
    (mkRow 0 b 0 0 0)
    (mkRow 0 0 b 0 0)
    (mkRow 0 0 0 1 0).

Definition contrast_matrix (c : Z) : ColorMatrix5x4 :=
  let offset := 128 * (1 - c) in
  mkMatrix
    (mkRow c 0 0 0 offset)
    (mkRow 0 c 0 0 offset)
    (mkRow 0 0 c 0 offset)
    (mkRow 0 0 0 1 0).

(** ** 4. Verification of Core Invariants *)

(** Theorem 1: Output channel is always bounded in [0, 255]. *)
Theorem clamp_channel_bounded : forall (v : Z),
  0 <= clamp_channel v <= 255.
Proof.
  intros v.
  unfold clamp_channel.
  lia.
Qed.

Theorem brightness_channel_bounded : forall (b x : Z),
  0 <= brightness_channel b x <= 255.
Proof.
  intros b x.
  unfold brightness_channel.
  apply clamp_channel_bounded.
Qed.

Theorem contrast_channel_bounded : forall (c x : Z),
  0 <= contrast_channel c x <= 255.
Proof.
  intros c x.
  unfold contrast_channel.
  apply clamp_channel_bounded.
Qed.

Theorem eval_color_matrix_valid : forall (m : ColorMatrix5x4) (p : RGBA),
  valid_rgba (eval_color_matrix m p).
Proof.
  intros m p.
  unfold valid_rgba, eval_color_matrix, eval_row, valid_channel; simpl.
  repeat split; apply clamp_channel_bounded.
Qed.

(** Theorem 2: Clamping a valid channel [0, 255] is the identity. *)
Lemma clamp_channel_id : forall (x : Z),
  valid_channel x -> clamp_channel x = x.
Proof.
  intros x Hvalid.
  unfold valid_channel, clamp_channel in *.
  lia.
Qed.

(** Theorem 3: brightness(1) is the identity operation on valid channels and pixels. *)
Theorem brightness_one_identity_channel : forall (x : Z),
  valid_channel x -> brightness_channel 1 x = x.
Proof.
  intros x Hvalid.
  unfold brightness_channel.
  replace (1 * x) with x by lia.
  apply clamp_channel_id; exact Hvalid.
Qed.

Theorem brightness_one_identity_rgba : forall (p : RGBA),
  valid_rgba p -> apply_brightness 1 p = p.
Proof.
  intros [r g b a] [Hr [Hg [Hb Ha]]].
  unfold apply_brightness; simpl in *.
  rewrite !brightness_one_identity_channel by assumption.
  rewrite clamp_channel_id by assumption.
  reflexivity.
Qed.

(** Theorem 4: contrast(1) is the identity operation on valid channels. *)
Theorem contrast_one_identity_channel : forall (x : Z),
  valid_channel x -> contrast_channel 1 x = x.
Proof.
  intros x Hvalid.
  unfold contrast_channel.
  replace (1 * (x - 128) + 128) with x by lia.
  apply clamp_channel_id; exact Hvalid.
Qed.

(** Theorem 5: Monotonicity of clamp_channel. *)
Lemma clamp_channel_monotonic : forall (u v : Z),
  u <= v -> clamp_channel u <= clamp_channel v.
Proof.
  intros u v Hle.
  unfold clamp_channel.
  lia.
Qed.

(** Theorem 6: brightness(b) is monotonic in [b] for non-negative inputs [x >= 0]. *)
Theorem brightness_monotonic_in_b : forall (b1 b2 x : Z),
  0 <= x ->
  b1 <= b2 ->
  brightness_channel b1 x <= brightness_channel b2 x.
Proof.
  intros b1 b2 x Hx Hb.
  unfold brightness_channel.
  apply clamp_channel_monotonic.
  apply Z.mul_le_mono_nonneg_r; assumption.
Qed.

(** Theorem 7: brightness(b) is monotonic in [x] for non-negative multiplier [b >= 0]. *)
Theorem brightness_monotonic_in_x : forall (b x1 x2 : Z),
  0 <= b ->
  x1 <= x2 ->
  brightness_channel b x1 <= brightness_channel b x2.
Proof.
  intros b x1 x2 Hb Hx.
  unfold brightness_channel.
  apply clamp_channel_monotonic.
  apply Z.mul_le_mono_nonneg_l; assumption.
Qed.

(** Theorem 8: Matrix builder lowering equivalence for brightness(b) and contrast(c). *)
Theorem brightness_matrix_equiv : forall (b : Z) (p : RGBA),
  eval_color_matrix (brightness_matrix b) p = apply_brightness b p.
Proof.
  intros b [r g bl a].
  unfold eval_color_matrix, brightness_matrix, apply_brightness,
         eval_row, brightness_channel;