(**
  BlinkShapePolygonSemantics.v
  Formal specification of Chromium Blink CSS shapes polygon ray-scanbeam intersection
  derived from third_party/blink/renderer/core/layout/shapes/polygon_shape.cc
  according to W3C CSS Shapes Module Level 1 (§3 Basic Shapes: polygon).
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

Record Segment2D := {
  seg_p1 : Point2D;
  seg_p2 : Point2D
}.

Record ShapeInterval := {
  interval_x1 : Z;
  interval_x2 : Z
}.

(** 1. Edge Scanbeam Intersection Calculation *)

Definition edge_y_min (seg : Segment2D) : Z :=
  Z.min seg.(seg_p1).(pt_y) seg.(seg_p2).(pt_y).

Definition edge_y_max (seg : Segment2D) : Z :=
  Z.max seg.(seg_p1).(pt_y) seg.(seg_p2).(pt_y).

Definition edge_is_active_at_y (seg : Segment2D) (y : Z) : bool :=
  (edge_y_min seg <=? y) && (y <=? edge_y_max seg) && (negb (seg.(seg_p1).(pt_y) =? seg.(seg_p2).(pt_y))).

Definition interpolate_edge_x (seg : Segment2D) (y : Z) : Z :=
  let x1 := seg.(seg_p1).(pt_x) in
  let y1 := seg.(seg_p1).(pt_y) in
  let x2 := seg.(seg_p2).(pt_x) in
  let y2 := seg.(seg_p2).(pt_y) in
  if y2 =? y1 then x1
  else x1 + (y - y1) * (x2 - x1) / (y2 - y1).

(** 2. Invariant Theorems *)

Theorem interpolate_edge_at_p1 :
  forall seg : Segment2D,
    seg.(seg_p1).(pt_y) <> seg.(seg_p2).(pt_y) ->
    interpolate_edge_x seg seg.(seg_p1).(pt_y) = seg.(seg_p1).(pt_x).
Proof.
  intros [p1 p2] Hdiff.
  unfold interpolate_edge_x.
  simpl in *.
  destruct (p2.(pt_y) =? p1.(pt_y)) eqn:Eeq.
  - apply Z.eqb_eq in Eeq. lia.
  - assert ((p1.(pt_y) - p1.(pt_y)) * (p2.(pt_x) - p1.(pt_x)) = 0) by lia.
    rewrite H.
    rewrite Z.div_0_l by lia.
    lia.
Qed.

Theorem interpolate_edge_at_p2 :
  forall seg : Segment2D,
    seg.(seg_p1).(pt_y) <> seg.(seg_p2).(pt_y) ->
    interpolate_edge_x seg seg.(seg_p2).(pt_y) = seg.(seg_p2).(pt_x).
Proof.
  intros [p1 p2] Hdiff.
  unfold interpolate_edge_x.
  simpl in *.
  destruct (p2.(pt_y) =? p1.(pt_y)) eqn:Eeq.
  - apply Z.eqb_eq in Eeq. lia.
  - rewrite Z.mul_comm.
    rewrite Z.div_mul by lia.
    lia.
Qed.

Theorem edge_inactive_outside_y_bounds :
  forall (seg : Segment2D) (y : Z),
    y < edge_y_min seg \/ edge_y_max seg < y ->
    edge_is_active_at_y seg y = false.
Proof.
  intros seg y Hout.
  unfold edge_is_active_at_y.
  destruct Hout as [Hbelow | Habove].
  - assert (H : (edge_y_min seg <=? y) = false).
    { apply Z.leb_gt. exact Hbelow. }
    rewrite H.
    simpl. reflexivity.
  - assert (H : (y <=? edge_y_max seg) = false).
    { apply Z.leb_gt. exact Habove. }
    rewrite H.
    destruct (edge_y_min seg <=? y); simpl; reflexivity.
Qed.

Definition make_shape_interval (x_a x_b : Z) : ShapeInterval := {|
  interval_x1 := Z.min x_a x_b;
  interval_x2 := Z.max x_a x_b
|}.

Theorem shape_interval_valid_order :
  forall x_a x_b : Z,
    let iv := make_shape_interval x_a x_b in
    iv.(interval_x1) <= iv.(interval_x2).
Proof.
  intros x_a x_b iv.
  unfold iv, make_shape_interval.
  simpl.
  lia.
Qed.
