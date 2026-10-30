Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Payment Validation Errors Emptiness Semantics *)
(** Payment Request API §5.8: PaymentValidationErrors dictionary *)

Record payment_validation_errors : Type := mk_errors {
  has_error            : bool;
  has_shipping_address : bool;
  has_payer_errors     : bool
}.

Definition has_no_validation_errors (e : payment_validation_errors) : bool :=
  negb (has_error e || has_shipping_address e || has_payer_errors e).

Theorem no_validation_errors_sound : forall e,
  has_no_validation_errors e = true <->
  has_error e = false /\ has_shipping_address e = false /\ has_payer_errors e = false.
Proof.
  intros [he hsa hpe].
  unfold has_no_validation_errors; simpl.
  destruct he; destruct hsa; destruct hpe; simpl; split; intro H; try discriminate; auto; try (destruct H as [? [? ?]]; discriminate).
Qed.
