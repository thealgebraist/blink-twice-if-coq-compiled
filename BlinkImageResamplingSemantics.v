(* ========================================================================= *)
(*               BlinkImageResamplingSemantics.v                             *)
(* ========================================================================= *)
(* Formal semantics of discrete image resampling and Porter-Duff             *)
(* alpha compositing in Chromium Blink & Skia.                               *)
(* Verified with Coq 9.3.0 with STRICTLY 0 admits.                           *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* ------------------------------------------------------------------------- *)
(* 1. Discrete Nearest-Neighbor Image Resampling Coordinate Mapping           *)
(* ------------------------------------------------------------------------- *)

(** Coordinate mapping from destination/target buffer to source image.
    For target coordinate target_x in [0, target_w), the sampled source
    coordinate is floor((target_x * src_w) / target_w). *)
Definition sample_nearest (target_x target_w src_w : Z) : Z :=
  (target_x * src_w) / target_w.

(** Key Theorem: Nearest-neighbor sampling maps valid target coordinates
    strictly into the valid source coordinate range [0, src_w). *)
Theorem sample_nearest_in_bounds : forall target_x target_w src_w : Z,
  0 <= target_x < target_w ->
  0 < src_w ->
  0 <= sample_nearest target_x target_w src_w < src_w.
Proof.
  intros target_x target_w src_w Htarget Hsrc.
  unfold sample_nearest.
  split.
  - apply Z.div_pos; nia.
  - apply Z.div_lt_upper_bound; [lia | nia].
Qed.

(** Nearest-neighbor mapping of origin maps to origin. *)
Theorem sample_nearest_origin : forall target_w src_w : Z,
  0 < target_w ->
  sample_nearest 0 target_w src_w = 0.
Proof.
  intros target_w src_w Hw.
  unfold sample_nearest.
  rewrite Z.mul_0_l.
  apply Z.div_0_l.
  lia.
Qed.

(** Monotonicity of nearest-neighbor coordinate mapping. *)
Theorem sample_nearest_monotone : forall target_x1 target_x2 target_w src_w : Z,
  0 <= target_x1 <= target_x2 ->
  0 < target_w ->
  0 <= src_w ->
  sample_nearest target_x1 target_w src_w <= sample_nearest target_x2 target_w src_w.
Proof.
  intros tx1 tx2 tw sw Hx Hw Hs.
  unfold sample_nearest.
  apply Z.div_le_mono; [lia | nia].
Qed.

(** 2D Nearest-Neighbor Resampling Mapping *)
Definition sample_nearest_2d (tx ty tw th sw sh : Z) : Z * Z :=
  (sample_nearest tx tw sw, sample_nearest ty th sh).

Theorem sample_nearest_2d_in_bounds : forall tx ty tw th sw sh : Z,
  0 <= tx < tw ->
  0 <= ty < th ->
  0 < sw ->
  0 < sh ->
  0 <= fst (sample_nearest_2d tx ty tw th sw sh) < sw /\
  0 <= snd (sample_nearest_2d tx ty tw th sw sh) < sh.
Proof.
  intros tx ty tw th sw sh Hx Hy Hsw Hsh.
  unfold sample_nearest_2d; simpl.
  split; apply sample_nearest_in_bounds; assumption.
Qed.

(* ------------------------------------------------------------------------- *)
(* 2. Bilinear Interpolation Weights in Fixed-Point 1/256 Arithmetic          *)
(* ------------------------------------------------------------------------- *)

(** In Skia/Blink 2D fixed-point interpolation, subpixel phase is represented
    as an integer in [0, 256], where 256 represents 1.0 (unit fraction). *)

(** 1D linear interpolation in 1/256 fixed-point arithmetic *)
Definition lerp256 (v0 v1 w : Z) : Z :=
  (v0 * (256 - w) + v1 * w) / 256.

Theorem lerp256_bounded : forall v0 v1 w : Z,
  0 <= v0 <= 255 ->
  0 <= v1 <= 255 ->
  0 <= w <= 256 ->
  0 <= lerp256 v0 v1 w <= 255.
Proof.
  intros v0 v1 w Hv0 Hv1 Hw.
  unfold lerp256.
  split.
  - apply Z.div_pos; nia.
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.

Theorem lerp256_zero_weight : forall v0 v1 : Z,
  lerp256 v0 v1 0 = v0.
Proof.
  intros v0 v1.
  unfold lerp256.
  replace (v0 * (256 - 0) + v1 * 0) with (v0 * 256) by ring.
  apply Z.div_mul; lia.
Qed.

Theorem lerp256_full_weight : forall v0 v1 : Z,
  lerp256 v0 v1 256 = v1.
Proof.
  intros v0 v1.
  unfold lerp256.
  replace (v0 * (256 - 256) + v1 * 256) with (v1 * 256) by ring.
  apply Z.div_mul; lia.
Qed.

(** 2D Bilinear Interpolation Weights:
    Each weight is the product of 1D linear weights along X and Y axes.
    The sum of all four weights equals 256 * 256 = 65536. *)
Definition bilinear_weight_00 (fx fy : Z) : Z := (256 - fx) * (256 - fy).
Definition bilinear_weight_10 (fx fy : Z) : Z := fx * (256 - fy).
Definition bilinear_weight_01 (fx fy : Z) : Z := (256 - fx) * fy.
Definition bilinear_weight_11 (fx fy : Z) : Z := fx * fy.

(** Weight Partition of Unity: weights always sum to 65536 *)
Theorem bilinear_weights_sum : forall fx fy : Z,
  bilinear_weight_00 fx fy +
  bilinear_weight_10 fx fy +
  bilinear_weight_01 fx fy +
  bilinear_weight_11 fx fy = 65536.
Proof.
  intros fx fy.
  unfold bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  ring.
Qed.

(** Non-negativity of bilinear weights for fractional phase in [0, 256] *)
Theorem bilinear_weights_nonneg : forall fx fy : Z,
  0 <= fx <= 256 ->
  0 <= fy <= 256 ->
  0 <= bilinear_weight_00 fx fy /\
  0 <= bilinear_weight_10 fx fy /\
  0 <= bilinear_weight_01 fx fy /\
  0 <= bilinear_weight_11 fx fy.
Proof.
  intros fx fy Hx Hy.
  unfold bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  repeat split; nia.
Qed.

(** Upper bound of bilinear weights *)
Theorem bilinear_weights_bounded : forall fx fy : Z,
  0 <= fx <= 256 ->
  0 <= fy <= 256 ->
  bilinear_weight_00 fx fy <= 65536 /\
  bilinear_weight_10 fx fy <= 65536 /\
  bilinear_weight_01 fx fy <= 65536 /\
  bilinear_weight_11 fx fy <= 65536.
Proof.
  intros fx fy Hx Hy.
  unfold bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  repeat split; nia.
Qed.

(** 2D Bilinear Resampling Interpolator *)
Definition bilinear_interp256 (c00 c10 c01 c11 fx fy : Z) : Z :=
  (c00 * bilinear_weight_00 fx fy +
   c10 * bilinear_weight_10 fx fy +
   c01 * bilinear_weight_01 fx fy +
   c11 * bilinear_weight_11 fx fy) / 65536.

(** Bilinear interpolation preserves valid 8-bit channel bounds [0, 255] *)
Theorem bilinear_interp256_bounded : forall c00 c10 c01 c11 fx fy : Z,
  0 <= c00 <= 255 ->
  0 <= c10 <= 255 ->
  0 <= c01 <= 255 ->
  0 <= c11 <= 255 ->
  0 <= fx <= 256 ->
  0 <= fy <= 256 ->
  0 <= bilinear_interp256 c00 c10 c01 c11 fx fy <= 255.
Proof.
  intros c00 c10 c01 c11 fx fy H00 H10 H01 H11 Hx Hy.
  unfold bilinear_interp256.
  assert (W0: 0 <= bilinear_weight_00 fx fy) by (unfold bilinear_weight_00; nia).
  assert (W1: 0 <= bilinear_weight_10 fx fy) by (unfold bilinear_weight_10; nia).
  assert (W2: 0 <= bilinear_weight_01 fx fy) by (unfold bilinear_weight_01; nia).
  assert (W3: 0 <= bilinear_weight_11 fx fy) by (unfold bilinear_weight_11; nia).
  split.
  - apply Z.div_pos; [|lia].
    nia.
  - apply Z.div_le_upper_bound; [lia |].
    assert (Hsum: c00 * bilinear_weight_00 fx fy +
                  c10 * bilinear_weight_10 fx fy +
                  c01 * bilinear_weight_01 fx fy +
                  c11 * bilinear_weight_11 fx fy <=
                  255 * (bilinear_weight_00 fx fy +
                         bilinear_weight_10 fx fy +
                         bilinear_weight_01 fx fy +
                         bilinear_weight_11 fx fy)) by nia.
    rewrite bilinear_weights_sum in Hsum.
    exact Hsum.
Qed.

(** Bilinear interpolation corner identities *)
Theorem bilinear_interp256_corner_00 : forall c00 c10 c01 c11 : Z,
  bilinear_interp256 c00 c10 c01 c11 0 0 = c00.
Proof.
  intros c00 c10 c01 c11.
  unfold bilinear_interp256, bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  replace (c00 * ((256 - 0) * (256 - 0)) +
           c10 * (0 * (256 - 0)) +
           c01 * ((256 - 0) * 0) +
           c11 * (0 * 0)) with (c00 * 65536) by ring.
  apply Z.div_mul; lia.
Qed.

Theorem bilinear_interp256_corner_10 : forall c00 c10 c01 c11 : Z,
  bilinear_interp256 c00 c10 c01 c11 256 0 = c10.
Proof.
  intros c00 c10 c01 c11.
  unfold bilinear_interp256, bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  replace (c00 * ((256 - 256) * (256 - 0)) +
           c10 * (256 * (256 - 0)) +
           c01 * ((256 - 256) * 0) +
           c11 * (256 * 0)) with (c10 * 65536) by ring.
  apply Z.div_mul; lia.
Qed.

Theorem bilinear_interp256_corner_01 : forall c00 c10 c01 c11 : Z,
  bilinear_interp256 c00 c10 c01 c11 0 256 = c01.
Proof.
  intros c00 c10 c01 c11.
  unfold bilinear_interp256, bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  replace (c00 * ((256 - 0) * (256 - 256)) +
           c10 * (0 * (256 - 256)) +
           c01 * ((256 - 0) * 256) +
           c11 * (0 * 256)) with (c01 * 65536) by ring.
  apply Z.div_mul; lia.
Qed.

Theorem bilinear_interp256_corner_11 : forall c00 c10 c01 c11 : Z,
  bilinear_interp256 c00 c10 c01 c11 256 256 = c11.
Proof.
  intros c00 c10 c01 c11.
  unfold bilinear_interp256, bilinear_weight_00, bilinear_weight_10, bilinear_weight_01, bilinear_weight_11.
  replace (c00 * ((256 - 256) * (256 - 256)) +
           c10 * (256 * (256 - 256)) +
           c01 * ((256 - 256) * 256) +
           c11 * (256 * 256)) with (c11 * 65536) by ring.
  apply Z.div_mul; lia.
Qed.

(* ------------------------------------------------------------------------- *)
(* 3. Porter-Duff Source-Over Alpha Compositing & Blending                   *)
(* ------------------------------------------------------------------------- *)

(** Porter-Duff source-over color channel alpha blending on integer RGBA [0, 255].
    Blends source color src_c with opacity src_a over destination color dst_c.
    dst_a is the destination alpha channel. *)
Definition alpha_blend (src_c src_a dst_c dst_a : Z) : Z :=
  (src_c * src_a + dst_c * (255 - src_a)) / 255.

(** Key Theorem: alpha_blend is strictly bounded in [0, 255] for all valid inputs. *)
Theorem alpha_blend_bounded : forall src_c src_a dst_c dst_a : Z,
  0 <= src_c <= 255 ->
  0 <= src_a <= 255 ->
  0 <= dst_c <= 255 ->
  0 <= dst_a <= 255 ->
  0 <= alpha_blend src_c src_a dst_c dst_a <= 255.
Proof.
  intros src_c src_a dst_c dst_a Hsc Hsa Hdc Hda.
  unfold alpha_blend.
  split.
  - apply Z.div_pos; nia.
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.

(** Key Theorem: When source is fully opaque (src_a = 255), alpha_blend returns src_c. *)
Theorem alpha_blend_opaque_src : forall src_c dst_c dst_a : Z,
  alpha_blend src_c 255 dst_c dst_a = src_c.
Proof.
  intros src_c dst_c dst_a.
  unfold alpha_blend.
  replace (src_c * 255 + dst_c * (255 - 255)) with (src_c * 255) by ring.
  apply Z.div_mul; lia.
Qed.

(** Implication form for when src_a = 255 *)
Theorem alpha_blend_opaque_src_when : forall src_c src_a dst_c dst_a : Z,
  src_a = 255 ->
  alpha_blend src_c src_a dst_c dst_a = src_c.
Proof.
  intros src_c src_a dst_c dst_a Hsa.
  subst src_a.
  apply alpha_blend_opaque_src.
Qed.

(** Key Theorem: When source is fully transparent (src_a = 0), alpha_blend returns dst_c. *)
Theorem alpha_blend_transparent_src : forall src_c dst_c dst_a : Z,
  alpha_blend src_c 0 dst_c dst_a = dst_c.
Proof.
  intros src_c dst_c dst_a.
  unfold alpha_blend.
  replace (src_c * 0 + dst_c * (255 - 0)) with (dst_c * 255) by ring.
  apply Z.div_mul; lia.
Qed.

(** Implication form for when src_a = 0 *)
Theorem alpha_blend_transparent_src_when : forall src_c src_a dst_c dst_a : Z,
  src_a = 0 ->
  alpha_blend src_c src_a dst_c dst_a = dst_c.
Proof.
  intros src_c src_a dst_c dst_a Hsa.
  subst src_a.
  apply alpha_blend_transparent_src.
Qed.

(** Porter-Duff Source-Over Alpha Channel Compositing:
    a_out = src_a + dst_a * (255 - src_a) / 255 *)
Definition alpha_composite (src_a dst_a : Z) : Z :=
  src_a + (dst_a * (255 - src_a)) / 255.

Theorem alpha_composite_bounded : forall src_a dst_a : Z,
  0 <= src_a <= 255 ->
  0 <= dst_a <= 255 ->
  0 <= alpha_composite src_a dst_a <= 255.
Proof.
  intros src_a dst_a Hsa Hda.
  unfold alpha_composite.
  split.
  - assert (0 <= (dst_a * (255 - src_a)) / 255) by (apply Z.div_pos; nia).
    lia.
  - apply Z.le_trans with (src_a + (255 * (255 - src_a)) / 255).
    + apply Z.add_le_mono_l.
      apply Z.div_le_mono; [lia | nia].
    + replace (255 * (255 - src_a)) with ((255 - src_a) * 255) by ring.
      rewrite Z.div_mul by lia.
      lia.
Qed.

Theorem alpha_composite_opaque_src : forall dst_a : Z,
  alpha_composite 255 dst_a = 255.
Proof.
  intros dst_a.
  unfold alpha_composite.
  replace (dst_a * (255 - 255)) with 0 by ring.
  rewrite Z.div_0_l by lia.
  lia.
Qed.

Theorem alpha_composite_transparent_src : forall dst_a : Z,
  0 <= dst_a <= 255 ->
  alpha_composite 0 dst_a = dst_a.
Proof.
  intros dst_a Hda.
  unfold alpha_composite.
  replace (dst_a * (255 - 0)) with (dst_a * 255) by ring.
  rewrite Z.div_mul by lia.
  lia.
Qed.

(** Complete RGBA Pixel Structure and Composition *)
Record RGBA : Type := mkRGBA {
  px_r : Z;
  px_g : Z;
  px_b : Z;
  px_a : Z
}.

Definition valid_rgba (p : RGBA) : Prop :=
  0 <= px_r p <= 255 /\
  0 <= px_g p <= 255 /\
  0 <= px_b p <= 255 /\
  0 <= px_a p <= 255.

Definition blend_rgba (src dst : RGBA) : RGBA := {|
  px_r := alpha_blend (px_r src) (px_a src) (px_r dst) (px_a dst);
  px_g := alpha_blend (px_g src) (px_a src) (px_g dst) (px_a dst);
  px_b := alpha_blend (px_b src) (px_a src) (px_b dst) (px_a dst);
  px_a := alpha_composite (px_a src) (px_a dst)
|}.

Theorem blend_rgba_preserves_valid : forall src dst : RGBA,
  valid_rgba src ->
  valid_rgba dst ->
  valid_rgba (blend_rgba src dst).
Proof.
  intros src dst [Hr1 [Hg1 [Hb1 Ha1]]] [Hr2 [Hg2 [Hb2 Ha2]]].
  unfold valid_rgba, blend_rgba; simpl.
  split; [apply alpha_blend_bounded; assumption |].
  split; [apply alpha_blend_bounded; assumption |].
  split; [apply alpha_blend_bounded; assumption |].
  apply alpha_composite_bounded; assumption.
Qed.
