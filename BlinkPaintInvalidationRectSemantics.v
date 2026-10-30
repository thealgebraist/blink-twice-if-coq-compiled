(**
  BlinkPaintInvalidationRectSemantics.v
  Formal specification of Chromium Blink paint invalidation and visual rect mapping
  derived from third_party/blink/renderer/core/paint/paint_invalidator.cc and paint_property_tree_builder.cc
  according to CSS 2.1 (§8 Box Dimensions) & CSS Containment Level 2.
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record PaintRect := {
  p_x : Z;
  p_y : Z;
  p_w : Z;
  p_h : Z
}.

Definition p_right (r : PaintRect) : Z :=
  r.(p_x) + r.(p_w).

Definition p_bottom (r : PaintRect) : Z :=
  r.(p_y) + r.(p_h).

Definition union_paint_rects (r1 r2 : PaintRect) : PaintRect :=
  let x_min := Z.min r1.(p_x) r2.(p_x) in
  let y_min := Z.min r1.(p_y) r2.(p_y) in
  let x_max := Z.max (p_right r1) (p_right r2) in
  let y_max := Z.max (p_bottom r1) (p_bottom r2) in
  {|
    p_x := x_min;
    p_y := y_min;
    p_w := x_max - x_min;
    p_h := y_max - y_min
  |}.

Definition point_in_rect (px py : Z) (r : PaintRect) : Prop :=
  r.(p_x) <= px < p_right r /\ r.(p_y) <= py < p_bottom r.

(** 1. Non-negativity Preservation *)

Theorem union_rects_dimensions_nonneg :
  forall r1 r2 : PaintRect,
    0 <= r1.(p_w) ->
    0 <= r1.(p_h) ->
    0 <= r2.(p_w) ->
    0 <= r2.(p_h) ->
    let u := union_paint_rects r1 r2 in
    0 <= u.(p_w) /\ 0 <= u.(p_h).
Proof.
  intros r1 r2 Hw1 Hh1 Hw2 Hh2 u.
  unfold u, union_paint_rects, p_right, p_bottom.
  simpl.
  split; lia.
Qed.

(** 2. Containment of Both Input Rectangles *)

Theorem union_contains_point_left :
  forall (r1 r2 : PaintRect) (px py : Z),
    0 <= r1.(p_w) ->
    0 <= r1.(p_h) ->
    0 <= r2.(p_w) ->
    0 <= r2.(p_h) ->
    point_in_rect px py r1 ->
    point_in_rect px py (union_paint_rects r1 r2).
Proof.
  intros r1 r2 px py Hw1 Hh1 Hw2 Hh2 [Hpx Hpy].
  unfold point_in_rect, union_paint_rects, p_right, p_bottom in *.
  simpl in *.
  split; lia.
Qed.

Theorem union_contains_point_right :
  forall (r1 r2 : PaintRect) (px py : Z),
    0 <= r1.(p_w) ->
    0 <= r1.(p_h) ->
    0 <= r2.(p_w) ->
    0 <= r2.(p_h) ->
    point_in_rect px py r2 ->
    point_in_rect px py (union_paint_rects r1 r2).
Proof.
  intros r1 r2 px py Hw1 Hh1 Hw2 Hh2 [Hpx Hpy].
  unfold point_in_rect, union_paint_rects, p_right, p_bottom in *.
  simpl in *.
  split; lia.
Qed.

(** 3. Commutativity and Associativity *)

Theorem union_paint_rects_comm :
  forall r1 r2 : PaintRect,
    union_paint_rects r1 r2 = union_paint_rects r2 r1.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold union_paint_rects, p_right, p_bottom.
  simpl.
  f_equal; lia.
Qed.

Theorem union_paint_rects_assoc :
  forall r1 r2 r3 : PaintRect,
    union_paint_rects (union_paint_rects r1 r2) r3 =
    union_paint_rects r1 (union_paint_rects r2 r3).
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2] [x3 y3 w3 h3].
  unfold union_paint_rects, p_right, p_bottom.
  simpl.
  f_equal; lia.
Qed.

