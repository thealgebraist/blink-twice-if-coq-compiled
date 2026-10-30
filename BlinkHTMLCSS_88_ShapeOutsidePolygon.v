(* Blink2Coq HTML/CSS Synthesis for ShapeOutsidePolygon *)
(* Source: renderer/core/layout/shapes/shape_outside_polygon.cc *)

From Stdlib Require Import ZArith Bool Lia. Open Scope Z_scope.
Definition is_valid_polygon (num_vertices : Z) : bool :=
  3 <=? num_vertices.
Theorem valid_polygon_has_area : forall v,
  is_valid_polygon v = true -> 3 <= v.
Proof.
  intros v H. unfold is_valid_polygon in H.
  apply Z.leb_le in H. exact H.
Qed.
