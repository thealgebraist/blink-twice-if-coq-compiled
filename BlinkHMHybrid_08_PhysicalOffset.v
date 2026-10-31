(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record PhysicalOffset := mkPhysicalOffset {
  physicaloffset_left : Z;
  physicaloffset_top : Z
}.

Definition translate_x (x1 : Z) (x2 : Z) : Z :=
  x1 + x2.

Theorem translate_x_assoc :
  forall (x1 x2 x3 : Z), translate_x (translate_x x1 x2) x3 = translate_x x1 (translate_x x2 x3).
Proof.
  intros x1 x2 x3. unfold translate_x. ring.
Qed.
