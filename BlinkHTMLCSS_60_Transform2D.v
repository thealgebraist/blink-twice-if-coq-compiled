(* Blink2Coq HTML/CSS Synthesis for Transform2D *)
(* Source: renderer/platform/transforms/transformation_matrix.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem translation_2d_comm : forall x dx1 dx2,
  (x + dx1) + dx2 = (x + dx2) + dx1.
Proof. intros. ring. Qed.
