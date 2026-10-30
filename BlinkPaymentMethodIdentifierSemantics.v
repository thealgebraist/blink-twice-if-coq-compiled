Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Payment Method Identifier Validation Semantics *)
(** Payment Method Identifiers §2: standardized vs URL-based *)

Inductive payment_method_kind : Type :=
| StandardizedMethod (id : Z)
| SecureURLMethod    (url_id : Z)
| InvalidMethod.

Definition is_valid_payment_method (m : payment_method_kind) : bool :=
  match m with
  | StandardizedMethod _ => true
  | SecureURLMethod _    => true
  | InvalidMethod        => false
  end.

Theorem standardized_method_valid : forall id,
  is_valid_payment_method (StandardizedMethod id) = true.
Proof.
  intro id. reflexivity.
Qed.

Theorem invalid_method_rejected :
  is_valid_payment_method InvalidMethod = false.
Proof.
  reflexivity.
Qed.
