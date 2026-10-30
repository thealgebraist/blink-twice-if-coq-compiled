### 1. Audit Summary: Chromium Blink `feColorMatrix` vs. W3C Filter Effects 1 §9

In W3C Filter Effects Module Level 1 (§9, `feColorMatrix`), the color transformation on an input pixel $(R, G, B, A)$—with component values normalized to $[0, 1]$ or scaled to $[0, 255]$—is defined via a $5 \times 4$ matrix $M$:

$$
\begin{bmatrix} R' \\ G' \\ B' \\ A' \\ 1 \end{bmatrix} = 
\begin{bmatrix} 
m_{00} & m_{01} & m_{02} & m_{03} & m_{04} \\
m_{10} & m_{11} & m_{12} & m_{13} & m_{14} \\
m_{20} & m_{21} & m_{22} & m_{23} & m_{24} \\
m_{30} & m_{31} & m_{32} & m_{33} & m_{34} \\
0 & 0 & 0 & 0 & 1 
\end{bmatrix}
\begin{bmatrix} R \\ G \\ B \\ A \\ 1 \end{bmatrix}
$$

In Chromium Blink (`third_party/blink/renderer/core/svg/svg_fe_color_matrix_element.cc` and `cc/paint/filter_operations.cc` delegating to `SkColorMatrixFilter`), the 20-element array is applied to pixel components, with the 5th column scaled by 255 when operating in 8-bit integer channel space $[0, 255]$, followed by clamping to $[0, 255]$.

#### Key Audited Properties:
1. **Identity Preservation:** When $M$ is the identity matrix ($m_{ii} = 1$ for $i \in \{0..3\}$ and $m_{ij} = 0$ otherwise), the affine color transform evaluates to the exact input vector $(R, G, B, A)$. If the input pixel is well-formed (channels within $[0, 255]$), post-transform clamping is a no-op and preserves the RGBA components identically.
2. **Channel Clamping Invariant:** For any arbitrary $5 \times 4$ integer/fixed-point matrix (including negative weights or large positive offsets), the output clamping stage strictly bounds every resulting channel $C' \in \{R', G', B', A'\}$ within the valid 8-bit unsigned integer range $[0, 255]$.

---

### 2. Formal Verification in Rocq / Coq (`BlinkSVGColorMatrixTransformSemantics.v`)

Below is the complete, self-contained Coq formalization verifying both the clamping invariants and identity matrix preservation with **0 admits**.

```coq
(** * BlinkSVGColorMatrixTransformSemantics.v
    Formal audit of Chromium Blink feColorMatrix vs W3C Filter Effects 1 §9.
    Verifies:
    1. Channel clamping invariants bounding outputs in [0, 255].
    2. Identity matrix exact preservation of valid RGBA pixels.
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Data Types and Definitions *)

(** An RGBA pixel represented in 8-bit integer space (modeled over Z). *)
Record Pixel : Type := mkPixel {
  pR : Z;
  pG : Z;
  pB : Z;
  pA : Z
}.

(** A pixel is valid if all its channels lie within [0, 255]. *)
Definition valid_pixel (p : Pixel) : Prop :=
  0 <= pR p <= 255 /\
  0 <= pG p <= 255 /\
  0 <= pB p <= 255 /\
  0 <= pA p <= 255.

(** A 5x4 Color Matrix as specified in W3C Filter Effects 1 §9.
    Offsets (m04, m14, m24, m34) are pre-scaled to [0, 255] domain. *)
Record ColorMatrix : Type := mkMatrix {
  m00 : Z; m01 : Z; m02 : Z; m03 : Z; m04 : Z;
  m10 : Z; m11 : Z; m12 : Z; m13 : Z; m14 : Z;
  m20 : Z; m21 : Z; m22 : Z; m23 : Z; m24 : Z;
  m30 : Z; m31 : Z; m32 : Z; m33 : Z; m34 : Z
}.

(** The W3C / Blink Identity Color Matrix. *)
Definition identity_matrix : ColorMatrix :=
  mkMatrix
    1 0 0 0 0
    0 1 0 0 0
    0 0 1 0 0
    0 0 0 1 0.

(** Channel clamping function bounding values to [0, 255]. *)
Definition clamp_channel (x : Z) : Z :=
  Z.max 0 (Z.min 255 x).

(** Row evaluation for a single channel given a pixel. *)
Definition eval_row (c0 c1 c2 c3 c4 : Z) (p : Pixel) : Z :=
  c0 * (pR p) + c1 * (pG p) + c2 * (pB p) + c3 * (pA p) + c4.

(** Full feColorMatrix transformation with output clamping. *)
Definition apply_color_matrix (m : ColorMatrix) (p : Pixel) : Pixel :=
  mkPixel
    (clamp_channel (eval_row (m00 m) (m01 m) (m02 m) (m03 m) (m04 m) p))
    (clamp_channel (eval_row (m10 m) (m11 m) (m12 m) (m13 m) (m14 m) p))
    (clamp_channel (eval_row (m20 m) (m21 m) (m22 m) (m23 m) (m24 m) p))
    (clamp_channel (eval_row (m30 m) (m31 m) (m32 m) (m33 m) (m34 m) p)).

(** ** 2. Clamping Invariants *)

(** Lemma: clamp_channel strictly bounds any integer within [0, 255]. *)
Lemma clamp_channel_bounds : forall (x : Z),
  0 <= clamp_channel x <= 255.
Proof.
  intros x.
  unfold clamp_channel.
  lia.
Qed.

(** Lemma: clamp_channel is an identity operation on values already in [0, 255]. *)
Lemma clamp_channel_id : forall (x : Z),
  0 <= x <= 255 ->
  clamp_channel x = x.
Proof.
  intros x Hbounds.
  unfold clamp_channel.
  lia.
Qed.

(** Theorem 1 (Invariants): For any ColorMatrix and any input Pixel,
    the transformed output pixel is guaranteed to have all channels in [0, 255]. *)
Theorem color_matrix_output_valid : forall (m : ColorMatrix) (p : Pixel),
  valid_pixel (apply_color_matrix m p).
Proof.
  intros m p.
  unfold valid_pixel, apply_color_matrix; simpl.
  repeat split; apply clamp_channel_bounds.
Qed.

(** ** 3. Identity Matrix Preservation *)

(** Lemma: Unclamped row evaluation with identity weights preserves each channel. *)
Lemma eval_row_identity : forall (p : Pixel),
  eval_row 1 0 0 0 0 p = pR p /\
  eval_row 0 1 0 0 0 p = pG p /\
  eval_row 0 0 1 0 0 p = pB p /\
  eval_row 0 0 0 1 0 p = pA p.
Proof.
  intros p.
  unfold eval_row.
  repeat split; lia.
Qed.

(** Theorem 2 (Identity Preservation): Applying the identity matrix to any
    valid pixel preserves its RGBA components exactly. *)
Theorem identity_matrix_preserves_pixel : forall (p : Pixel),
  valid_pixel p ->
  apply_color_matrix identity_matrix p = p.
Proof.
  intros [r g b a] [Hr [Hg [Hb Ha]]].
  unfold apply_color_matrix, identity_matrix, eval_row; simpl in *.
  replace (1 * r + 0 * g + 0 * b + 0 * a + 0) with r by lia.
  replace (0 * r + 1 * g + 0 * b + 0 * a + 0) with g by lia.
  replace (0 * r + 0 * g + 1 * b + 0 * a + 0) with b by lia.
  replace (0 * r + 0 * g + 0 * b + 1 * a + 0) with a by lia.
  rewrite (clamp_channel_id r Hr).
  rewrite (clamp_channel_id g Hg).
  rewrite (clamp_channel_id b Hb).
  rewrite (clamp_channel_id a Ha).
  reflexivity.
Qed.

(** Corollary: Applying the identity matrix is idempotent on arbitrary pixels. *)
Corollary identity_matrix_idempotent : forall (p : Pixel),
  apply_color_matrix identity_matrix (apply_color_matrix identity_matrix p) =
  apply_color_matrix identity_matrix p.
Proof.
  intros p.
  apply identity_matrix_preserves_pixel.
  apply color_matrix_output_valid.
Qed.
```