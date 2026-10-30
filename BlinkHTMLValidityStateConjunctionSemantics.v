Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink ValidityState Check Semantics *)
(** HTML Standard §4.10.21: validity boolean logic *)

Definition is_valid_form_control (e1 e2 e3 : bool) : bool :=
  negb (orb (orb e1 e2) e3).

Theorem valid_when_no_errors :
  is_valid_form_control false false false = true.
Proof.
  reflexivity.
Qed.

Theorem invalid_when_any_error : forall e2 e3,
  is_valid_form_control true e2 e3 = false.
Proof.
  intros e2 e3; reflexivity.
Qed.
