Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Transform Invertibility Semantics *)
(** HTML Canvas 2D §2: 2x2 matrix determinant calculation *)

Definition matrix_determinant (a b c d : Z) : Z :=
  a * d - b * c.

Theorem identity_matrix_det_is_one :
  matrix_determinant 1 0 0 1 = 1.
Proof.
  unfold matrix_determinant; reflexivity.
Qed.
