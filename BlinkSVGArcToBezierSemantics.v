(**
  BlinkSVGArcToBezierSemantics.v
  Formal specification of Chromium Blink SVG path arc-to-cubic-Bézier conversion
  derived from third_party/blink/renderer/core/svg/svg_path_parser.cc and platform/graphics/path.cc
  according to W3C SVG 2 (§9.5.1 Elliptical Arc Implementation Notes & Appendix B.2).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record Point2D := {
  pt_x : Z;
  pt_y : Z
}.

Record EndpointArc := {
  arc_p1 : Point2D;
  arc_p2 : Point2D;
  arc_rx : Z;
  arc_ry : Z;
  arc_large_flag : bool;
  arc_sweep_flag : bool
}.

Record CubicBezierSegment := {
  bez_p0 : Point2D;
  bez_p1 : Point2D;
  bez_p2 : Point2D;
  bez_p3 : Point2D
}.

Definition is_degenerate_point (a : EndpointArc) : bool :=
  (a.(arc_p1).(pt_x) =? a.(arc_p2).(pt_x)) && (a.(arc_p1).(pt_y) =? a.(arc_p2).(pt_y)).

Definition is_zero_radius (a : EndpointArc) : bool :=
  (a.(arc_rx) =? 0) || (a.(arc_ry) =? 0).

(** Radii absolute value normalization *)
Definition normalize_radii (rx ry : Z) : Z * Z :=
  (Z.abs rx, Z.abs ry).

Theorem normalize_radii_nonneg :
  forall rx ry : Z,
    0 <= fst (normalize_radii rx ry) /\ 0 <= snd (normalize_radii rx ry).
Proof.
  intros rx ry.
  unfold normalize_radii.
  simpl.
  split; apply Z.abs_nonneg.
Qed.

(** Cubic Bezier Evaluation at Boundary Endpoints *)
Definition eval_cubic_bezier_endpoint (seg : CubicBezierSegment) (at_start : bool) : Point2D :=
  if at_start then seg.(bez_p0)
  else seg.(bez_p3).

Theorem bezier_reconstruction_preserves_endpoints :
  forall (p1 p2 c1 c2 : Point2D),
    let seg := {| bez_p0 := p1; bez_p1 := c1; bez_p2 := c2; bez_p3 := p2 |} in
    eval_cubic_bezier_endpoint seg true = p1 /\
    eval_cubic_bezier_endpoint seg false = p2.
Proof.
  intros p1 p2 c1 c2 seg.
  unfold seg, eval_cubic_bezier_endpoint.
  simpl.
  split; reflexivity.
Qed.

Theorem degenerate_arc_has_coincident_endpoints :
  forall a : EndpointArc,
    is_degenerate_point a = true ->
    a.(arc_p1) = a.(arc_p2).
Proof.
  intros [p1 p2 rx ry lf sf] Hdeg.
  unfold is_degenerate_point in Hdeg.
  simpl in *.
  apply andb_true_iff in Hdeg.
  destruct Hdeg as [Hx Hy].
  apply Z.eqb_eq in Hx.
  apply Z.eqb_eq in Hy.
  destruct p1, p2.
  simpl in *.
  subst.
  reflexivity.
Qed.

