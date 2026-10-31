(* ========================================================================= *)
(*                  BlinkGlyphRasterizerSemantics.v                          *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Glyph Atlas Rasterization,         *)
(* Quadratic Bézier Curve Scan-Conversion, 2D Coverage Calculation, and      *)
(* Atlas Pixel Blitting per OpenType / TrueType rasterization semantics.     *)
(* Strictly constructive, fully verified with 0 admits.                      *)
(* ========================================================================= *)

From Stdlib Require Import ZArith List Bool.Bool Lia.
Import ListNotations.
Open Scope Z_scope.

(** * 1. Quadratic Bézier Scanline Evaluation *)
(** TrueType font glyph outlines are composed of straight lines and         *)
(** second-order (quadratic) Bézier splines defined by control points       *)
(** p0 (start), p1 (control), and p2 (end).                                 *)
(** B(t) = (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2, t in [0, 1].   *)
(** Discretized with rational parameter t = t_num / t_den:                  *)
(** let u := t_den - t_num in                                               *)
(** B(t_num, t_den) = (u^2 * p0 + 2*u*t_num*p1 + t_num^2 * p2) / t_den^2.  *)

Definition eval_bezier_coord (c0 c1 c2 : Z) (t_num t_den : Z) : Z :=
  let u := t_den - t_num in
  (u * u * c0 + 2 * u * t_num * c1 + t_num * t_num * c2) / (t_den * t_den).

Definition eval_bezier_2d (p0 p1 p2 : Z * Z) (t_num t_den : Z) : Z * Z :=
  (eval_bezier_coord (fst p0) (fst p1) (fst p2) t_num t_den,
   eval_bezier_coord (snd p0) (snd p1) (snd p2) t_num t_den).

(** * 2. 2D Glyph Coverage Calculation *)
(** Anti-aliased font rasterizers (e.g. FreeType / Skia / Blink) compute     *)
(** subpixel fractional coverage per cell, normalized to an 8-bit alpha      *)
(** mask in range [0, 255].                                                 *)

Definition glyph_coverage (mask : Z -> Z -> Z) (gx gy : Z) : Z :=
  Z.max 0 (Z.min 255 (mask gx gy)).

(** * 3. Glyph Atlas Pixel Blitting *)
(** Blending a glyph texel onto a destination background buffer             *)
(** using linear interpolation (lerp) weighted by coverage:                  *)
(** blit = (text_color * coverage + bg_color * (255 - coverage)) / 255.     *)

Definition blit_glyph_pixel (bg_color text_color coverage : Z) : Z :=
  (text_color * coverage + bg_color * (255 - coverage)) / 255.

(** * 4. Coordinate Translation & Atlas Packing *)
Record GlyphMetrics := mkGlyphMetrics {
  gm_width     : Z;
  gm_height    : Z;
  gm_bearing_x : Z;
  gm_bearing_y : Z;
  gm_advance_x : Z
}.

Definition atlas_target_coord (atlas_x atlas_y gx gy : Z) : Z * Z :=
  (atlas_x + gx, atlas_y + gy).

(** * 5. Theorems & Formal Properties *)

(** 5.1 Bézier Endpoint Theorems *)

Lemma eval_bezier_coord_start : forall c0 c1 c2 t_den,
  0 < t_den ->
  eval_bezier_coord c0 c1 c2 0 t_den = c0.
Proof.
  intros c0 c1 c2 t_den Hden.
  unfold eval_bezier_coord.
  replace (t_den - 0) with t_den by lia.
  replace (t_den * t_den * c0 + 2 * t_den * 0 * c1 + 0 * 0 * c2)
    with (c0 * (t_den * t_den)) by ring.
  apply Z.div_mul.
  nia.
Qed.

Lemma eval_bezier_coord_end : forall c0 c1 c2 t_den,
  0 < t_den ->
  eval_bezier_coord c0 c1 c2 t_den t_den = c2.
Proof.
  intros c0 c1 c2 t_den Hden.
  unfold eval_bezier_coord.
  replace (t_den - t_den) with 0 by lia.
  replace (0 * 0 * c0 + 2 * 0 * t_den * c1 + t_den * t_den * c2)
    with (c2 * (t_den * t_den)) by ring.
  apply Z.div_mul.
  nia.
Qed.

Theorem bezier_endpoint_start : forall (p0 p1 p2 : Z * Z) (t_den : Z),
  0 < t_den ->
  eval_bezier_2d p0 p1 p2 0 t_den = p0.
Proof.
  intros [x0 y0] p1 p2 t_den Hden.
  unfold eval_bezier_2d. simpl.
  f_equal; apply eval_bezier_coord_start; exact Hden.
Qed.

Theorem bezier_endpoint_end : forall (p0 p1 p2 : Z * Z) (t_den : Z),
  0 < t_den ->
  eval_bezier_2d p0 p1 p2 t_den t_den = p2.
Proof.
  intros p0 p1 [x2 y2] t_den Hden.
  unfold eval_bezier_2d. simpl.
  f_equal; apply eval_bezier_coord_end; exact Hden.
Qed.

Theorem bezier_endpoints : forall (p0 p1 p2 : Z * Z) (t_den : Z),
  0 < t_den ->
  eval_bezier_2d p0 p1 p2 0 t_den = p0 /\
  eval_bezier_2d p0 p1 p2 t_den t_den = p2.
Proof.
  intros p0 p1 p2 t_den Hden.
  split.
  - apply bezier_endpoint_start; exact Hden.
  - apply bezier_endpoint_end; exact Hden.
Qed.

(** Bézier Midpoint (t = 1/2) Property *)
Theorem eval_bezier_midpoint : forall c0 c1 c2 t_half,
  0 < t_half ->
  eval_bezier_coord c0 c1 c2 t_half (2 * t_half) = (c0 + 2 * c1 + c2) / 4.
Proof.
  intros c0 c1 c2 t_half Hpos.
  unfold eval_bezier_coord.
  replace (2 * t_half - t_half) with t_half by lia.
  replace (t_half * t_half * c0 + 2 * t_half * t_half * c1 + t_half * t_half * c2)
    with ((t_half * t_half) * (c0 + 2 * c1 + c2)) by ring.
  replace (2 * t_half * (2 * t_half))
    with ((t_half * t_half) * 4) by ring.
  apply Z.div_mul_cancel_l; [lia | nia].
Qed.

(** Degenerate Bézier line (all control points identical) *)
Theorem eval_bezier_degenerate_line : forall c t_num t_den,
  0 <= t_num <= t_den ->
  0 < t_den ->
  eval_bezier_coord c c c t_num t_den = c.
Proof.
  intros c t_num t_den Ht Hden.
  unfold eval_bezier_coord.
  set (u := t_den - t_num).
  assert (Hu : u = t_den - t_num) by reflexivity.
  replace (u * u * c + 2 * u * t_num * c + t_num * t_num * c)
    with (c * (u + t_num) * (u + t_num)) by ring.
  replace (u + t_num) with t_den by lia.
  replace (c * t_den * t_den) with (c * (t_den * t_den)) by ring.
  apply Z.div_mul.
  nia.
Qed.

(** 5.2 Glyph Coverage Theorems *)

Theorem glyph_coverage_bounds : forall mask gx gy,
  0 <= glyph_coverage mask gx gy <= 255.
Proof.
  intros mask gx gy.
  unfold glyph_coverage.
  lia.
Qed.

Theorem glyph_coverage_idempotent : forall mask gx gy,
  0 <= mask gx gy <= 255 ->
  glyph_coverage mask gx gy = mask gx gy.
Proof.
  intros mask gx gy H.
  unfold glyph_coverage.
  lia.
Qed.

Theorem glyph_coverage_clamped_min : forall mask gx gy,
  mask gx gy <= 0 ->
  glyph_coverage mask gx gy = 0.
Proof.
  intros mask gx gy H.
  unfold glyph_coverage.
  lia.
Qed.

Theorem glyph_coverage_clamped_max : forall mask gx gy,
  255 <= mask gx gy ->
  glyph_coverage mask gx gy = 255.
Proof.
  intros mask gx gy H.
  unfold glyph_coverage.
  lia.
Qed.

(** 5.3 Glyph Blit Theorems *)

Theorem blit_glyph_full_coverage : forall (bg_color text_color : Z),
  blit_glyph_pixel bg_color text_color 255 = text_color.
Proof.
  intros bg_color text_color.
  unfold blit_glyph_pixel.
  replace (text_color * 255 + bg_color * (255 - 255)) with (text_color * 255) by ring.
  apply Z.div_mul.
  lia.
Qed.

Theorem blit_glyph_zero_coverage : forall (bg_color text_color : Z),
  blit_glyph_pixel bg_color text_color 0 = bg_color.
Proof.
  intros bg_color text_color.
  unfold blit_glyph_pixel.
  replace (text_color * 0 + bg_color * (255 - 0)) with (bg_color * 255) by ring.
  apply Z.div_mul.
  lia.
Qed.

Theorem blit_glyph_coverage_bounds : forall (bg_color text_color coverage : Z),
  0 <= bg_color <= 255 ->
  0 <= text_color <= 255 ->
  0 <= coverage <= 255 ->
  0 <= blit_glyph_pixel bg_color text_color coverage <= 255.
Proof.
  intros bg_color text_color coverage Hbg Htxt Hcov.
  unfold blit_glyph_pixel.
  split.
  - apply Z.div_pos.
    + nia.
    + lia.
  - apply Z.div_le_upper_bound.
    + lia.
    + nia.
Qed.

Theorem blit_glyph_same_color : forall (color coverage : Z),
  0 <= coverage <= 255 ->
  blit_glyph_pixel color color coverage = color.
Proof.
  intros color coverage Hcov.
  unfold blit_glyph_pixel.
  replace (color * coverage + color * (255 - coverage)) with (color * 255) by ring.
  apply Z.div_mul.
  lia.
Qed.

Theorem blit_glyph_monotonic : forall bg_color text_color cov1 cov2,
  bg_color <= text_color ->
  0 <= cov1 <= cov2 ->
  cov2 <= 255 ->
  blit_glyph_pixel bg_color text_color cov1 <= blit_glyph_pixel bg_color text_color cov2.
Proof.
  intros bg text cov1 cov2 Hcol Hcov12 Hcov2.
  unfold blit_glyph_pixel.
  apply Z.div_le_mono.
  - lia.
  - nia.
Qed.

(******************************************************************************)


(******************************************************************************)
(* 6. CHROMIUM SKIA FONT GAMMA CORRECTION (SK_GAMMA_EXPONENT 1.4f)           *)
(******************************************************************************)

(** Chromium and Skia FreeType font rasterizers apply a non-linear gamma     *)
(** transfer function with exponent gamma = 1.4 (SK_GAMMA_EXPONENT) to       *)
(** linear FreeType coverage bytes to prevent visual thinning of glyph       *)
(** stem edges:                                                              *)
(** alpha_corrected = round(255 * (alpha_linear / 255) ^ (1 / 1.4)).         *)

Definition skia_gamma_lut : list Z := [
  0%Z; 5%Z; 8%Z; 11%Z; 13%Z; 15%Z; 18%Z; 20%Z; 22%Z; 23%Z; 25%Z; 27%Z; 29%Z; 30%Z; 32%Z; 34%Z;
  35%Z; 37%Z; 38%Z; 40%Z; 41%Z; 43%Z; 44%Z; 46%Z; 47%Z; 49%Z; 50%Z; 51%Z; 53%Z; 54%Z; 55%Z; 57%Z;
  58%Z; 59%Z; 60%Z; 62%Z; 63%Z; 64%Z; 65%Z; 67%Z; 68%Z; 69%Z; 70%Z; 72%Z; 73%Z; 74%Z; 75%Z; 76%Z;
  77%Z; 78%Z; 80%Z; 81%Z; 82%Z; 83%Z; 84%Z; 85%Z; 86%Z; 87%Z; 89%Z; 90%Z; 91%Z; 92%Z; 93%Z; 94%Z;
  95%Z; 96%Z; 97%Z; 98%Z; 99%Z; 100%Z; 101%Z; 102%Z; 103%Z; 104%Z; 105%Z; 106%Z; 107%Z; 108%Z; 109%Z; 110%Z;
  111%Z; 112%Z; 113%Z; 114%Z; 115%Z; 116%Z; 117%Z; 118%Z; 119%Z; 120%Z; 121%Z; 122%Z; 123%Z; 124%Z; 125%Z; 126%Z;
  127%Z; 128%Z; 129%Z; 130%Z; 131%Z; 132%Z; 133%Z; 133%Z; 134%Z; 135%Z; 136%Z; 137%Z; 138%Z; 139%Z; 140%Z; 141%Z;
  142%Z; 143%Z; 143%Z; 144%Z; 145%Z; 146%Z; 147%Z; 148%Z; 149%Z; 150%Z; 151%Z; 151%Z; 152%Z; 153%Z; 154%Z; 155%Z;
  156%Z; 157%Z; 158%Z; 158%Z; 159%Z; 160%Z; 161%Z; 162%Z; 163%Z; 164%Z; 164%Z; 165%Z; 166%Z; 167%Z; 168%Z; 169%Z;
  170%Z; 170%Z; 171%Z; 172%Z; 173%Z; 174%Z; 175%Z; 175%Z; 176%Z; 177%Z; 178%Z; 179%Z; 180%Z; 180%Z; 181%Z; 182%Z;
  183%Z; 184%Z; 184%Z; 185%Z; 186%Z; 187%Z; 188%Z; 188%Z; 189%Z; 190%Z; 191%Z; 192%Z; 192%Z; 193%Z; 194%Z; 195%Z;
  196%Z; 196%Z; 197%Z; 198%Z; 199%Z; 200%Z; 200%Z; 201%Z; 202%Z; 203%Z; 204%Z; 204%Z; 205%Z; 206%Z; 207%Z; 207%Z;
  208%Z; 209%Z; 210%Z; 211%Z; 211%Z; 212%Z; 213%Z; 214%Z; 214%Z; 215%Z; 216%Z; 217%Z; 217%Z; 218%Z; 219%Z; 220%Z;
  220%Z; 221%Z; 222%Z; 223%Z; 223%Z; 224%Z; 225%Z; 226%Z; 226%Z; 227%Z; 228%Z; 229%Z; 229%Z; 230%Z; 231%Z; 232%Z;
  232%Z; 233%Z; 234%Z; 235%Z; 235%Z; 236%Z; 237%Z; 238%Z; 238%Z; 239%Z; 240%Z; 241%Z; 241%Z; 242%Z; 243%Z; 243%Z;
  244%Z; 245%Z; 246%Z; 246%Z; 247%Z; 248%Z; 249%Z; 249%Z; 250%Z; 251%Z; 251%Z; 252%Z; 253%Z; 254%Z; 254%Z; 255%Z
].


Definition skia_gamma_correct (coverage : Z) : Z :=
  nth (Z.to_nat (Z.max 0 (Z.min 255 coverage))) skia_gamma_lut 0.

Definition blit_glyph_pixel_gamma (bg_color text_color coverage : Z) : Z :=
  blit_glyph_pixel bg_color text_color (skia_gamma_correct coverage).

Lemma skia_gamma_length : length skia_gamma_lut = 256%nat.
Proof. reflexivity. Qed.

Lemma skia_gamma_0 : skia_gamma_correct 0 = 0.
Proof. reflexivity. Qed.

Lemma skia_gamma_255 : skia_gamma_correct 255 = 255.
Proof. reflexivity. Qed.

Fixpoint check_bounds (l : list Z) : bool :=
  match l with
  | [] => true
  | x :: xs => (0 <=? x) && (x <=? 255) && check_bounds xs
  end.

Lemma check_bounds_lut : check_bounds skia_gamma_lut = true.
Proof. reflexivity. Qed.

Lemma check_bounds_nth : forall l n d,
  check_bounds l = true ->
  (n < length l)%nat ->
  0 <= nth n l d <= 255.
Proof.
  induction l as [| x xs IH]; intros n d Hchk Hlen.
  - simpl in Hlen. lia.
  - destruct n as [| n'].
    + simpl in Hchk.
      apply andb_true_iff in Hchk as [H1 H2].
      apply andb_true_iff in H1 as [Hge Hle].
      apply Z.leb_le in Hge.
      apply Z.leb_le in Hle.
      simpl. lia.
    + simpl in Hlen.
      simpl in Hchk.
      apply andb_true_iff in Hchk as [H1 H2].
      apply (IH n' d H2).
      lia.
Qed.

Theorem skia_gamma_bounds : forall coverage : Z,
  0 <= skia_gamma_correct coverage <= 255.
Proof.
  intros cov.
  unfold skia_gamma_correct.
  apply check_bounds_nth.
  - apply check_bounds_lut.
  - rewrite skia_gamma_length.
    change 256%nat with (Z.to_nat 256).
    apply Z2Nat.inj_lt; lia.
Qed.

Fixpoint check_boost (l : list Z) (i : nat) : bool :=
  match l with
  | [] => true
  | x :: xs => (Z.of_nat i <=? x) && check_boost xs (S i)
  end.

Lemma check_boost_lut : check_boost skia_gamma_lut 0%nat = true.
Proof. reflexivity. Qed.

Lemma check_boost_nth : forall l i n d,
  check_boost l i = true ->
  (n < length l)%nat ->
  Z.of_nat i + Z.of_nat n <= nth n l d.
Proof.
  induction l as [| x xs IH]; intros i n d Hchk Hlen.
  - simpl in Hlen. lia.
  - destruct n as [| n'].
    + simpl in Hchk.
      apply andb_true_iff in Hchk as [Hge Hrec].
      apply Z.leb_le in Hge.
      simpl. lia.
    + simpl in Hlen.
      simpl in Hchk.
      apply andb_true_iff in Hchk as [Hge Hrec].
      specialize (IH (S i) n' d Hrec ltac:(lia)).
      change (nth (S n') (x :: xs) d) with (nth n' xs d).
      lia.
Qed.

(** Contrast Boost Property: Gamma correction with gamma = 1.4 (> 1) strictly *)
(** increases or preserves edge coverage, eliminating glyph visual thinning.  *)
Theorem skia_gamma_contrast_boost : forall cov : Z,
  0 <= cov <= 255 ->
  cov <= skia_gamma_correct cov.
Proof.
  intros cov Hcov.
  unfold skia_gamma_correct.
  replace (Z.to_nat (Z.max 0 (Z.min 255 cov))) with (Z.to_nat cov) by lia.
  assert (Hlen : (Z.to_nat cov < length skia_gamma_lut)%nat).
  { rewrite skia_gamma_length.
    change 256%nat with (Z.to_nat 256).
    apply Z2Nat.inj_lt; [lia | lia | lia]. }
  pose proof (check_boost_nth skia_gamma_lut 0%nat (Z.to_nat cov) 0 check_boost_lut Hlen) as H.
  rewrite Z2Nat.id in H by lia.
  change (Z.of_nat 0) with 0 in H.
  lia.
Qed.

Theorem blit_glyph_gamma_full_coverage : forall bg_color text_color,
  blit_glyph_pixel_gamma bg_color text_color 255 = text_color.
Proof.
  intros bg text.
  unfold blit_glyph_pixel_gamma.
  rewrite skia_gamma_255.
  apply blit_glyph_full_coverage.
Qed.

Theorem blit_glyph_gamma_zero_coverage : forall bg_color text_color,
  blit_glyph_pixel_gamma bg_color text_color 0 = bg_color.
Proof.
  intros bg text.
  unfold blit_glyph_pixel_gamma.
  rewrite skia_gamma_0.
  apply blit_glyph_zero_coverage.
Qed.

Theorem blit_glyph_gamma_bounds : forall bg_color text_color coverage,
  0 <= bg_color <= 255 ->
  0 <= text_color <= 255 ->
  0 <= coverage <= 255 ->
  0 <= blit_glyph_pixel_gamma bg_color text_color coverage <= 255.
Proof.
  intros bg text cov Hbg Htxt Hcov.
  unfold blit_glyph_pixel_gamma.
  apply blit_glyph_coverage_bounds.
  - exact Hbg.
  - exact Htxt.
  - apply skia_gamma_bounds.
Qed.
