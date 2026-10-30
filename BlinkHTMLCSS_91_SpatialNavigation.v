(* Blink2Coq HTML/CSS Synthesis for SpatialNavigation *)
(* Source: renderer/core/page/spatial_navigation.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition manhattan_dist (x1 y1 x2 y2 : Z) : Z :=
  Z.abs (x1 - x2) + Z.abs (y1 - y2).
Theorem manhattan_dist_symmetric : forall x1 y1 x2 y2,
  manhattan_dist x1 y1 x2 y2 = manhattan_dist x2 y2 x1 y1.
Proof. intros. unfold manhattan_dist. lia. Qed.
