(**
  BlinkTransformMatrixSemantics.v
  Formal specification of Chromium Blink CSS 2D affine transformation matrix algebra
  derived from third_party/blink/renderer/platform/transforms/affine_transform.cc
  according to W3C CSS Transforms Module Level 1 (§5 & §6 2D Transformation Operations).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. 2D Affine Transformation Matrix Representation *)
(** Represents [[a, c, e], [b, d, f], [0, 0, 1]] *)
Record AffineTransform2D := {
  mat_a : Z;
  mat_b : Z;
  mat_c : Z;
  mat_d : Z;
  mat_e : Z;
  mat_f : Z
}.

Record Point2D := {
  pt_x : Z;
  pt_y : Z
}.

Definition identity_transform : AffineTransform2D := {|
  mat_a := 1;
  mat_b := 0;
  mat_c := 0;
  mat_d := 1;
  mat_e := 0;
  mat_f := 0
|}.

Definition make_translation (tx ty : Z) : AffineTransform2D := {|
  mat_a := 1;
  mat_b := 0;
  mat_c := 0;
  mat_d := 1;
  mat_e := tx;
  mat_f := ty
|}.

Definition make_scale (sx sy : Z) : AffineTransform2D := {|
  mat_a := sx;
  mat_b := 0;
  mat_c := 0;
  mat_d := sy;
  mat_e := 0;
  mat_f := 0
|}.

Definition map_point (m : AffineTransform2D) (p : Point2D) : Point2D := {|
  pt_x := m.(mat_a) * p.(pt_x) + m.(mat_c) * p.(pt_y) + m.(mat_e);
  pt_y := m.(mat_b) * p.(pt_x) + m.(mat_d) * p.(pt_y) + m.(mat_f)
|}.

Definition multiply_transform (m1 m2 : AffineTransform2D) : AffineTransform2D := {|
  mat_a := m1.(mat_a) * m2.(mat_a) + m1.(mat_c) * m2.(mat_b);
  mat_b := m1.(mat_b) * m2.(mat_a) + m1.(mat_d) * m2.(mat_b);
  mat_c := m1.(mat_a) * m2.(mat_c) + m1.(mat_c) * m2.(mat_d);
  mat_d := m1.(mat_b) * m2.(mat_c) + m1.(mat_d) * m2.(mat_d);
  mat_e := m1.(mat_a) * m2.(mat_e) + m1.(mat_c) * m2.(mat_f) + m1.(mat_e);
  mat_f := m1.(mat_b) * m2.(mat_e) + m1.(mat_d) * m2.(mat_f) + m1.(mat_f)
|}.

Definition determinant (m : AffineTransform2D) : Z :=
  m.(mat_a) * m.(mat_d) - m.(mat_b) * m.(mat_c).

(** 2. Identity Laws *)

Theorem identity_maps_identically :
  forall p : Point2D,
    map_point identity_transform p = p.
Proof.
  intros [px py].
  unfold map_point, identity_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f pt_x pt_y].
  f_equal; ring.
Qed.

Theorem identity_multiplication_left :
  forall m : AffineTransform2D,
    multiply_transform identity_transform m = m.
Proof.
  intros [a b c d e f].
  unfold multiply_transform, identity_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f].
  f_equal; ring.
Qed.

Theorem identity_multiplication_right :
  forall m : AffineTransform2D,
    multiply_transform m identity_transform = m.
Proof.
  intros [a b c d e f].
  unfold multiply_transform, identity_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f].
  f_equal; ring.
Qed.

(** 3. Associativity and Functoriality *)

Theorem transform_multiplication_assoc :
  forall m1 m2 m3 : AffineTransform2D,
    multiply_transform (multiply_transform m1 m2) m3 =
    multiply_transform m1 (multiply_transform m2 m3).
Proof.
  intros [a1 b1 c1 d1 e1 f1] [a2 b2 c2 d2 e2 f2] [a3 b3 c3 d3 e3 f3].
  unfold multiply_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f].
  f_equal; ring.
Qed.

Theorem map_point_composition :
  forall (m1 m2 : AffineTransform2D) (p : Point2D),
    map_point m1 (map_point m2 p) = map_point (multiply_transform m1 m2) p.
Proof.
  intros [a1 b1 c1 d1 e1 f1] [a2 b2 c2 d2 e2 f2] [px py].
  unfold map_point, multiply_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f pt_x pt_y].
  f_equal; ring.
Qed.

(** 4. Determinant Multiplicativity *)

Theorem determinant_identity :
  determinant identity_transform = 1.
Proof.
  unfold determinant, identity_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f].
  lia.
Qed.

Theorem determinant_multiplicativity :
  forall m1 m2 : AffineTransform2D,
    determinant (multiply_transform m1 m2) = determinant m1 * determinant m2.
Proof.
  intros [a1 b1 c1 d1 e1 f1] [a2 b2 c2 d2 e2 f2].
  unfold determinant, multiply_transform.
  cbn [mat_a mat_b mat_c mat_d mat_e mat_f].
  ring.
Qed.
