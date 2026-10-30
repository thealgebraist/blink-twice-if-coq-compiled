(******************************************************************************)
(* BlinkSVGSizingSemantics.v                                                  *)
(* Sound Formal Specification for SVG ViewBox Aspect Ratio Scaling           *)
(* Corresponding to:                                                          *)
(* 1. W3C SVG 2 Section 7.7 (The 'preserveAspectRatio' Attribute)            *)
(* 2. W3C SVG 2 Section 7.12 (Sizing SVG Content in CSS Box Model)           *)
(* 3. Blink LayoutSVGRoot (`third_party/blink/renderer/core/layout/svg/      *)
(*    layout_svg_root.cc`) and SVGPreserveAspectRatio                         *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Inductive SVGAlign : Type :=
  | SVGAlignNone
  | SVGAlignXMinYMin
  | SVGAlignXMidYMin
  | SVGAlignXMaxYMin
  | SVGAlignXMinYMid
  | SVGAlignXMidYMid
  | SVGAlignXMaxYMid
  | SVGAlignXMinYMax
  | SVGAlignXMidYMax
  | SVGAlignXMaxYMax.

Inductive SVGMeetOrSlice : Type :=
  | SVGMeet
  | SVGSlice.

Record SVGPreserveAspectRatio := mkSVGPreserveAspectRatio {
  par_align : SVGAlign;
  par_meet_or_slice : SVGMeetOrSlice
}.

Record SVGViewBox := mkSVGViewBox {
  vb_min_x : Z;
  vb_min_y : Z;
  vb_width : Z;
  vb_height : Z
}.

Record TransformedViewport := mkTransformedViewport {
  tv_offset_x : Z;
  tv_offset_y : Z;
  tv_scale_x_num : Z;
  tv_scale_x_den : Z;
  tv_scale_y_num : Z;
  tv_scale_y_den : Z
}.

(** Resolves uniform scale factor and alignment offsets according to W3C SVG 2 §7.7 *)
Definition compute_svg_transform (container_w container_h : Z)
                                 (vb : SVGViewBox)
                                 (par : SVGPreserveAspectRatio) : TransformedViewport :=
  let w := vb_width vb in
  let h := vb_height vb in
  if (w <=? 0) || (h <=? 0) then
    (* Invalid viewBox fallback: identity mapping *)
    mkTransformedViewport 0 0 1 1 1 1
  else
    match par_align par with
    | SVGAlignNone =>
        (* Non-uniform scaling *)
        mkTransformedViewport 0 0 container_w w container_h h
    | _ =>
        (* Uniform scaling *)
        let comp := (container_w * h) - (container_h * w) in
        let (s_num, s_den) := match par_meet_or_slice par with
                              | SVGMeet =>
                                  if comp <=? 0 then (container_w, w) (* container is narrower: w determines scale *)
                                  else (container_h, h)               (* container is taller *)
                              | SVGSlice =>
                                  if comp <=? 0 then (container_h, h) (* slice takes larger scale *)
                                  else (container_w, w)
                              end in
        let fitted_w := Z.quot (w * s_num) s_den in
        let fitted_h := Z.quot (h * s_num) s_den in
        let dx := match par_align par with
                  | SVGAlignXMinYMin | SVGAlignXMinYMid | SVGAlignXMinYMax => 0
                  | SVGAlignXMidYMin | SVGAlignXMidYMid | SVGAlignXMidYMax => Z.quot (container_w - fitted_w) 2
                  | SVGAlignXMaxYMin | SVGAlignXMaxYMid | SVGAlignXMaxYMax => container_w - fitted_w
                  | SVGAlignNone => 0
                  end in
        let dy := match par_align par with
                  | SVGAlignXMinYMin | SVGAlignXMidYMin | SVGAlignXMaxYMin => 0
                  | SVGAlignXMinYMid | SVGAlignXMidYMid | SVGAlignXMaxYMid => Z.quot (container_h - fitted_h) 2
                  | SVGAlignXMinYMax | SVGAlignXMidYMax | SVGAlignXMaxYMax => container_h - fitted_h
                  | SVGAlignNone => 0
                  end in
        mkTransformedViewport dx dy s_num s_den s_num s_den
    end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem compute_svg_transform_deterministic :
  forall cw ch vb par r1 r2,
    compute_svg_transform cw ch vb par = r1 ->
    compute_svg_transform cw ch vb par = r2 ->
    r1 = r2.
Proof.
  intros cw ch vb par r1 r2 H1 H2.
  subst. reflexivity.
Qed.

Theorem svg_scale_denominators_positive :
  forall cw ch vb par,
    0 < vb_width vb ->
    0 < vb_height vb ->
    let tv := compute_svg_transform cw ch vb par in
    0 < tv_scale_x_den tv /\ 0 < tv_scale_y_den tv.
Proof.
  intros cw ch vb par Hw Hh.
  unfold compute_svg_transform.
  assert (Hw_le : (vb_width vb <=? 0) = false) by (apply Z.leb_gt; assumption).
  assert (Hh_le : (vb_height vb <=? 0) = false) by (apply Z.leb_gt; assumption).
  rewrite Hw_le, Hh_le. simpl.
  destruct (par_align par); simpl; try (split; assumption).
  all: destruct (par_meet_or_slice par); simpl;
       destruct (cw * vb_height vb - ch * vb_width vb <=? 0);
       simpl; split; assumption.
Qed.
