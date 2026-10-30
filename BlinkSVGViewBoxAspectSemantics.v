(**
  BlinkSVGViewBoxAspectSemantics.v
  Formal specification of Chromium Blink SVG viewBox and preserveAspectRatio resolution
  derived from third_party/blink/renderer/core/layout/svg/layout_svg_root.cc
  and core/svg/svg_preserve_aspect_ratio.cc
  according to W3C SVG 2 (§7.7 preserveAspectRatio meet vs slice).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Definition kScale : Z := 1024.

Inductive SVGMeetOrSlice : Type :=
  | SVG_Meet
  | SVG_Slice.

Inductive SVGAlign : Type :=
  | SVG_Align_Min
  | SVG_Align_Mid
  | SVG_Align_Max.

Record ViewBox := {
  vb_w : Z;
  vb_h : Z
}.

Record Viewport := {
  vp_w : Z;
  vp_h : Z
}.

Definition compute_uniform_scale (vb : ViewBox) (vp : Viewport) (mos : SVGMeetOrSlice) : Z :=
  let rx := vp.(vp_w) * kScale / vb.(vb_w) in
  let ry := vp.(vp_h) * kScale / vb.(vb_h) in
  match mos with
  | SVG_Meet  => Z.min rx ry
  | SVG_Slice => Z.max rx ry
  end.

Definition fitted_dimension (vb_dim scale : Z) : Z :=
  vb_dim * scale / kScale.

Definition compute_align_offset (avail_dim fitted_dim : Z) (align : SVGAlign) : Z :=
  let delta := avail_dim - fitted_dim in
  match align with
  | SVG_Align_Min => 0
  | SVG_Align_Mid => delta / 2
  | SVG_Align_Max => delta
  end.

(** Theorems on Meet Scaling: Fitted box is contained within viewport *)

Theorem meet_scale_horizontal_contained :
  forall (vb : ViewBox) (vp : Viewport),
    0 < vb.(vb_w) ->
    0 < vb.(vb_h) ->
    0 <= vp.(vp_w) ->
    0 <= vp.(vp_h) ->
    let scale := compute_uniform_scale vb vp SVG_Meet in
    fitted_dimension vb.(vb_w) scale <= vp.(vp_w).
Proof.
  intros vb vp Hw Hh Hvpw Hvph scale.
  unfold scale, compute_uniform_scale, fitted_dimension, kScale.
  pose proof (Z.le_min_l (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h))) as Hle.
  assert (Hscale_nonneg : 0 <= Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h))).
  {
    apply Z.min_glb.
    - apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia|lia].
    - apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia|lia].
  }
  assert (Hprod : vb.(vb_w) * Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h))
                  <= vb.(vb_w) * (vp.(vp_w) * 1024 / vb.(vb_w))).
  { apply Z.mul_le_mono_nonneg_l; lia. }
  assert (Hcancel : vb.(vb_w) * (vp.(vp_w) * 1024 / vb.(vb_w)) <= vp.(vp_w) * 1024).
  { apply Z.mul_div_le; lia. }
  assert (Hstep : vb.(vb_w) * Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h)) <= vp.(vp_w) * 1024) by lia.
  assert (Hdiv : vb.(vb_w) * Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h)) / 1024 <= (vp.(vp_w) * 1024) / 1024).
  { apply Z.div_le_mono; [lia | exact Hstep]. }
  rewrite Z.div_mul in Hdiv by lia.
  exact Hdiv.
Qed.

Theorem meet_scale_vertical_contained :
  forall (vb : ViewBox) (vp : Viewport),
    0 < vb.(vb_w) ->
    0 < vb.(vb_h) ->
    0 <= vp.(vp_w) ->
    0 <= vp.(vp_h) ->
    let scale := compute_uniform_scale vb vp SVG_Meet in
    fitted_dimension vb.(vb_h) scale <= vp.(vp_h).
Proof.
  intros vb vp Hw Hh Hvpw Hvph scale.
  unfold scale, compute_uniform_scale, fitted_dimension, kScale.
  pose proof (Z.le_min_r (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h))) as Hle.
  assert (Hscale_nonneg : 0 <= Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h))).
  {
    apply Z.min_glb.
    - apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia|lia].
    - apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia|lia].
  }
  assert (Hprod : vb.(vb_h) * Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h))
                  <= vb.(vb_h) * (vp.(vp_h) * 1024 / vb.(vb_h))).
  { apply Z.mul_le_mono_nonneg_l; lia. }
  assert (Hcancel : vb.(vb_h) * (vp.(vp_h) * 1024 / vb.(vb_h)) <= vp.(vp_h) * 1024).
  { apply Z.mul_div_le; lia. }
  assert (Hstep : vb.(vb_h) * Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h)) <= vp.(vp_h) * 1024) by lia.
  assert (Hdiv : vb.(vb_h) * Z.min (vp.(vp_w) * 1024 / vb.(vb_w)) (vp.(vp_h) * 1024 / vb.(vb_h)) / 1024 <= (vp.(vp_h) * 1024) / 1024).
  { apply Z.div_le_mono; [lia | exact Hstep]. }
  rewrite Z.div_mul in Hdiv by lia.
  exact Hdiv.
Qed.

(** Meet alignment offset bounds *)
Theorem meet_align_offset_in_bounds :
  forall avail fitted align,
    0 <= fitted <= avail ->
    0 <= compute_align_offset avail fitted align <= avail - fitted.
Proof.
  intros avail fitted align Hbound.
  unfold compute_align_offset.
  assert (Hdelta : 0 <= avail - fitted) by lia.
  destruct align; simpl.
  - lia.
  - split.
    + apply Z.div_pos; lia.
    + assert (Hdiv : (avail - fitted) / 2 <= ((avail - fitted) * 2) / 2).
      { apply Z.div_le_mono; lia. }
      rewrite Z.div_mul in Hdiv by lia.
      exact Hdiv.
  - lia.
Qed.
