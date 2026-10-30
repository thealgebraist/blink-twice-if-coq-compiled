#!/usr/bin/env python3
"""
create_wave24_theories.py - Generate 16 formal Coq theories for Wave 24 with strictly 0 admits.
Theme: Blink SVG Filter & Vector Layout Semantics
"""

theories = {
    "BlinkSVGGaussianBlurSpreadSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feGaussianBlur Kernel Spread Radius Semantics *)
(** Filter Effects 1 §8: feGaussianBlur stdDeviation bounds *)

Definition stddev_to_kernel_radius (std_dev : Z) : Z :=
  if std_dev <=? 0 then 0
  else (3 * std_dev + 1) / 2.

Definition blur_outset_dimension (size r : Z) : Z :=
  size + 2 * r.

Theorem kernel_radius_nonneg : forall std_dev,
  0 <= std_dev ->
  0 <= stddev_to_kernel_radius std_dev.
Proof.
  intros std_dev Hsd.
  unfold stddev_to_kernel_radius.
  destruct (std_dev <=? 0) eqn:Heq.
  - lia.
  - apply Z.leb_gt in Heq.
    assert (0 <= (3 * std_dev + 1) / 2) by (apply Z.div_le_lower_bound; lia).
    lia.
Qed.

Theorem blur_outset_monotonic : forall size r,
  0 <= size ->
  0 <= r ->
  size <= blur_outset_dimension size r.
Proof.
  intros size r Hsize Hr.
  unfold blur_outset_dimension.
  lia.
Qed.
""",

    "BlinkSVGColorMatrixTransformSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feColorMatrix 5x4 Affine Color Transform Semantics *)
(** Filter Effects 1 §9: feColorMatrix channel clamping into [0, 255] *)

Record RGBAColor := {
  red : Z;
  green : Z;
  blue : Z;
  alpha : Z
}.

Definition clamp255 (v : Z) : Z :=
  Z.max 0 (Z.min 255 v).

Definition apply_identity_color_matrix (c : RGBAColor) : RGBAColor :=
  {| red := clamp255 (red c);
     green := clamp255 (green c);
     blue := clamp255 (blue c);
     alpha := clamp255 (alpha c) |}.

Theorem clamp255_bounds : forall v,
  0 <= clamp255 v <= 255.
Proof.
  intros v.
  unfold clamp255.
  lia.
Qed.

Theorem identity_matrix_preserves_valid_color : forall c,
  0 <= red c <= 255 ->
  0 <= green c <= 255 ->
  0 <= blue c <= 255 ->
  0 <= alpha c <= 255 ->
  apply_identity_color_matrix c = c.
Proof.
  intros c Hr Hg Hb Ha.
  unfold apply_identity_color_matrix, clamp255.
  destruct c as [r g b a]; simpl in *.
  assert (Z.max 0 (Z.min 255 r) = r) by lia.
  assert (Z.max 0 (Z.min 255 g) = g) by lia.
  assert (Z.max 0 (Z.min 255 b) = b) by lia.
  assert (Z.max 0 (Z.min 255 a) = a) by lia.
  rewrite H, H0, H1, H2.
  reflexivity.
Qed.
""",

    "BlinkSVGOffsetTranslationSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feOffset Translation Semantics *)
(** Filter Effects 1 §10: feOffset translation invariance *)

Record SVGRect := {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

Definition translate_svg_rect (rect : SVGRect) (dx dy : Z) : SVGRect :=
  {| rx := rx rect + dx;
     ry := ry rect + dy;
     rw := rw rect;
     rh := rh rect |}.

Theorem offset_preserves_dimensions : forall rect dx dy,
  rw (translate_svg_rect rect dx dy) = rw rect /\
  rh (translate_svg_rect rect dx dy) = rh rect.
Proof.
  intros rect dx dy.
  destruct rect; simpl; split; reflexivity.
Qed.

Theorem offset_composition_additive : forall rect dx1 dy1 dx2 dy2,
  translate_svg_rect (translate_svg_rect rect dx1 dy1) dx2 dy2 =
  translate_svg_rect rect (dx1 + dx2) (dy1 + dy2).
Proof.
  intros [x y w h] dx1 dy1 dx2 dy2.
  unfold translate_svg_rect; simpl.
  f_equal.
  - lia.
  - lia.
Qed.
""",

    "BlinkSVGBlendModeSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feBlend Mode Semantics *)
(** Filter Effects 1 §11: feBlend multiply & screen modes *)

Definition blend_multiply (c1 c2 : Z) : Z :=
  (c1 * c2) / 255.

Definition blend_screen (c1 c2 : Z) : Z :=
  255 - ((255 - c1) * (255 - c2)) / 255.

Theorem multiply_mode_bounded : forall c1 c2,
  0 <= c1 <= 255 ->
  0 <= c2 <= 255 ->
  0 <= blend_multiply c1 c2 <= 255.
Proof.
  intros c1 c2 H1 H2.
  unfold blend_multiply.
  assert (0 <= c1 * c2) by (apply Z.mul_nonneg_nonneg; lia).
  assert (c1 * c2 <= 255 * 255) by (apply Z.mul_le_mono_nonneg; lia).
  split.
  - apply Z.div_le_lower_bound; lia.
  - apply Z.div_le_upper_bound; lia.
Qed.

Theorem screen_mode_bounded : forall c1 c2,
  0 <= c1 <= 255 ->
  0 <= c2 <= 255 ->
  0 <= blend_screen c1 c2 <= 255.
Proof.
  intros c1 c2 H1 H2.
  unfold blend_screen.
  assert (0 <= 255 - c1 <= 255) by lia.
  assert (0 <= 255 - c2 <= 255) by lia.
  assert (0 <= (255 - c1) * (255 - c2)) by (apply Z.mul_nonneg_nonneg; lia).
  assert ((255 - c1) * (255 - c2) <= 255 * 255) by (apply Z.mul_le_mono_nonneg; lia).
  assert (0 <= ((255 - c1) * (255 - c2)) / 255) by (apply Z.div_le_lower_bound; lia).
  assert (((255 - c1) * (255 - c2)) / 255 <= 255) by (apply Z.div_le_upper_bound; lia).
  split; lia.
Qed.
""",

    "BlinkSVGCompositeArithmeticSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feComposite Arithmetic Mode Semantics *)
(** Filter Effects 1 §12: feComposite arithmetic clamping *)

Definition clamp_channel (val : Z) : Z :=
  Z.max 0 (Z.min 255 val).

Definition composite_arithmetic_unclamped (k1 k2 k3 k4 i1 i2 : Z) : Z :=
  k1 * i1 * i2 / 255 + k2 * i1 + k3 * i2 + k4.

Definition composite_arithmetic (k1 k2 k3 k4 i1 i2 : Z) : Z :=
  clamp_channel (composite_arithmetic_unclamped k1 k2 k3 k4 i1 i2).

Theorem composite_arithmetic_in_bounds : forall k1 k2 k3 k4 i1 i2,
  0 <= composite_arithmetic k1 k2 k3 k4 i1 i2 <= 255.
Proof.
  intros k1 k2 k3 k4 i1 i2.
  unfold composite_arithmetic, clamp_channel.
  lia.
Qed.

Theorem clamp_channel_idempotent : forall v,
  clamp_channel (clamp_channel v) = clamp_channel v.
Proof.
  intros v.
  unfold clamp_channel.
  lia.
Qed.
""",

    "BlinkSVGTurbulenceNoiseSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feTurbulence Noise Generation Semantics *)
(** Filter Effects 1 §13: feTurbulence pseudo-random bounds *)

Definition clamp_noise_to_byte (noise_val : Z) : Z :=
  Z.max 0 (Z.min 255 noise_val).

Theorem noise_to_byte_strictly_bounded : forall n,
  0 <= clamp_noise_to_byte n <= 255.
Proof.
  intros n.
  unfold clamp_noise_to_byte.
  lia.
Qed.

Theorem noise_valid_in_range_preserved : forall n,
  0 <= n <= 255 ->
  clamp_noise_to_byte n = n.
Proof.
  intros n Hn.
  unfold clamp_noise_to_byte.
  lia.
Qed.
""",

    "BlinkSVGDisplacementMapSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feDisplacementMap Coordinate Mapping Semantics *)
(** Filter Effects 1 §14: displacement mapping identity under scale=0 *)

Record Point2D := {
  px : Z;
  py : Z
}.

Definition displace_coordinate (pos : Point2D) (scale x_channel y_channel : Z) : Point2D :=
  {| px := px pos + scale * (x_channel - 128) / 256;
     py := py pos + scale * (y_channel - 128) / 256 |}.

Theorem zero_scale_is_identity : forall pos xc yc,
  displace_coordinate pos 0 xc yc = pos.
Proof.
  intros [x y] xc yc.
  unfold displace_coordinate; simpl.
  change (0 / 256) with 0.
  f_equal; lia.
Qed.
""",

    "BlinkSVGMorphologyRadiusSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feMorphology Dilate and Erode Semantics *)
(** Filter Effects 1 §15: Morphology dilation and erosion *)

Definition morphology_dilate (v r : Z) : Z :=
  v + Z.max 0 r.

Definition morphology_erode (v r : Z) : Z :=
  v - Z.max 0 r.

Theorem dilate_expands : forall v r,
  0 <= r ->
  v <= morphology_dilate v r.
Proof.
  intros v r Hr.
  unfold morphology_dilate.
  assert (Z.max 0 r = r) by (apply Z.max_r; lia).
  rewrite H; lia.
Qed.

Theorem erode_shrinks : forall v r,
  0 <= r ->
  morphology_erode v r <= v.
Proof.
  intros v r Hr.
  unfold morphology_erode.
  assert (Z.max 0 r = r) by (apply Z.max_r; lia).
  rewrite H; lia.
Qed.

Theorem zero_radius_identity : forall v,
  morphology_dilate v 0 = v /\ morphology_erode v 0 = v.
Proof.
  intros v.
  unfold morphology_dilate, morphology_erode.
  split; lia.
Qed.
""",

    "BlinkSVGDropShadowBoundsSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feDropShadow Bounds Expansion Semantics *)
(** Filter Effects 1 §16: feDropShadow bounding box union *)

Record SVGBounds := {
  b_min_x : Z;
  b_min_y : Z;
  b_max_x : Z;
  b_max_y : Z
}.

Definition union_svg_bounds (b1 b2 : SVGBounds) : SVGBounds :=
  {| b_min_x := Z.min (b_min_x b1) (b_min_x b2);
     b_min_y := Z.min (b_min_y b1) (b_min_y b2);
     b_max_x := Z.max (b_max_x b1) (b_max_x b2);
     b_max_y := Z.max (b_max_y b1) (b_max_y b2) |}.

Theorem union_contains_left : forall b1 b2,
  b_min_x (union_svg_bounds b1 b2) <= b_min_x b1 /\
  b_max_x b1 <= b_max_x (union_svg_bounds b1 b2).
Proof.
  intros b1 b2.
  unfold union_svg_bounds; simpl.
  split; lia.
Qed.

Theorem union_contains_right : forall b1 b2,
  b_min_x (union_svg_bounds b1 b2) <= b_min_x b2 /\
  b_max_x b2 <= b_max_x (union_svg_bounds b1 b2).
Proof.
  intros b1 b2.
  unfold union_svg_bounds; simpl.
  split; lia.
Qed.
""",

    "BlinkSVGConvolveMatrixSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feConvolveMatrix Normalization Semantics *)
(** Filter Effects 1 §17: Divisor normalization and clamping *)

Definition convolve_normalize (sum_kernel explicit_divisor : Z) : Z :=
  if explicit_divisor =? 0 then
    if sum_kernel =? 0 then 1 else sum_kernel
  else explicit_divisor.

Definition convolve_pixel (sum_val divisor : Z) : Z :=
  let d := if divisor =? 0 then 1 else divisor in
  Z.max 0 (Z.min 255 (sum_val / d)).

Theorem convolve_pixel_bounded : forall sum_val divisor,
  0 <= convolve_pixel sum_val divisor <= 255.
Proof.
  intros sum_val divisor.
  unfold convolve_pixel.
  lia.
Qed.

Theorem convolve_zero_divisor_fallback_nonzero : forall s,
  0 < s ->
  convolve_normalize s 0 = s.
Proof.
  intros s Hs.
  unfold convolve_normalize; simpl.
  destruct (s =? 0) eqn:Heq.
  - apply Z.eqb_eq in Heq; lia.
  - reflexivity.
Qed.
""",

    "BlinkSVGSpecularLightingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feSpecularLighting Phong Model Semantics *)
(** Filter Effects 1 §18: Phong reflection intensity *)

Definition clamp_specular_intensity (intensity : Z) : Z :=
  Z.max 0 (Z.min 255 intensity).

Theorem specular_intensity_bounded : forall i,
  0 <= clamp_specular_intensity i <= 255.
Proof.
  intros i.
  unfold clamp_specular_intensity.
  lia.
Qed.
""",

    "BlinkSVGDiffuseLightingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feDiffuseLighting Lambertian Model Semantics *)
(** Filter Effects 1 §19: Lambertian cosine reflection bounds *)

Definition lambertian_diffuse (kd dot_nl : Z) : Z :=
  let positive_dot := Z.max 0 dot_nl in
  let raw := (kd * positive_dot) / 255 in
  Z.max 0 (Z.min 255 raw).

Theorem lambertian_diffuse_bounded : forall kd dot_nl,
  0 <= kd <= 255 ->
  0 <= lambertian_diffuse kd dot_nl <= 255.
Proof.
  intros kd dot_nl Hkd.
  unfold lambertian_diffuse.
  lia.
Qed.
""",

    "BlinkSVGTileRepetitionSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feTile Pattern Repetition Semantics *)
(** Filter Effects 1 §20: Modulo seamless texture repetition *)

Definition tile_coordinate (p tile_size : Z) : Z :=
  p mod tile_size.

Theorem tile_coord_in_bounds : forall p tile_size,
  0 < tile_size ->
  0 <= tile_coordinate p tile_size < tile_size.
Proof.
  intros p tile_size Hts.
  unfold tile_coordinate.
  apply Z.mod_pos_bound.
  lia.
Qed.

Theorem tile_periodic : forall p tile_size,
  0 < tile_size ->
  tile_coordinate (p + tile_size) tile_size = tile_coordinate p tile_size.
Proof.
  intros p tile_size Hts.
  unfold tile_coordinate.
  replace (p + tile_size) with (p + 1 * tile_size) by lia.
  apply Z_mod_plus_full.
Qed.
""",

    "BlinkSVGPathMonotonicitySemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SVG Path Parser and Bounding Box Semantics *)
(** SVG 2 §9: Path bounding box enclosure *)

Record BoundingBox := {
  bb_min_x : Z;
  bb_max_x : Z
}.

Definition update_bbox_x (bb : BoundingBox) (x : Z) : BoundingBox :=
  {| bb_min_x := Z.min (bb_min_x bb) x;
     bb_max_x := Z.max (bb_max_x bb) x |}.

Theorem update_bbox_encloses_point : forall bb x,
  bb_min_x (update_bbox_x bb x) <= x <= bb_max_x (update_bbox_x bb x).
Proof.
  intros bb x.
  unfold update_bbox_x; simpl.
  split; lia.
Qed.

Theorem update_bbox_preserves_prior_bounds : forall bb x,
  bb_min_x (update_bbox_x bb x) <= bb_min_x bb /\
  bb_max_x bb <= bb_max_x (update_bbox_x bb x).
Proof.
  intros bb x.
  unfold update_bbox_x; simpl.
  split; lia.
Qed.
""",

    "BlinkSVGMarkerOrientationSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SVG Marker Auto-Start-Reverse Semantics *)
(** SVG 2 §11.6.2: 180-degree start marker reversal involution *)

Definition reverse_marker_angle (deg : Z) : Z :=
  (deg + 180) mod 360.

Theorem reverse_marker_involution : forall deg,
  reverse_marker_angle (reverse_marker_angle deg) = deg mod 360.
Proof.
  intros deg.
  unfold reverse_marker_angle.
  rewrite Zplus_mod_idemp_l.
  replace (deg + 180 + 180) with (deg + 1 * 360) by lia.
  rewrite Z_mod_plus_full.
  reflexivity.
Qed.
""",

    "BlinkSVGClippathMaskIntersectionSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SVG ClipPath and Mask Intersection Semantics *)
(** SVG 2 §14.3: Clip intersection bounding box containment *)

Record ClipRect := {
  c_left : Z;
  c_right : Z
}.

Definition intersect_clip (r1 r2 : ClipRect) : ClipRect :=
  {| c_left := Z.max (c_left r1) (c_left r2);
     c_right := Z.min (c_right r1) (c_right r2) |}.

Definition clip_width (r : ClipRect) : Z :=
  Z.max 0 (c_right r - c_left r).

Theorem intersect_width_bounded_left : forall r1 r2,
  clip_width (intersect_clip r1 r2) <= clip_width r1.
Proof.
  intros r1 r2.
  unfold clip_width, intersect_clip; simpl.
  lia.
Qed.

Theorem intersect_width_bounded_right : forall r1 r2,
  clip_width (intersect_clip r1 r2) <= clip_width r2.
Proof.
  intros r1 r2.
  unfold clip_width, intersect_clip; simpl.
  lia.
Qed.
"""
}

def main():
    print("Writing 16 formal Coq theories for Wave 24...")
    for filename, code in theories.items():
        with open(filename, "w") as f:
            f.write(code)
        print(f"  -> Wrote {filename}")
    print("Wave 24 Coq theories successfully written.")

if __name__ == "__main__":
    main()
