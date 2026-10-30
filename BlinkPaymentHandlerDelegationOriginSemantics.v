Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Payment Handler Delegation Origin Semantics *)
(** Payment Handler API §4.1 delegated payment client origin *)

Definition is_authorized_payment_handler (client_origin handler_origin : Z) : bool :=
  client_origin =? handler_origin.

Theorem payment_handler_authorization_sound : forall client handler,
  is_authorized_payment_handler client handler = true <-> client = handler.
Proof.
  intros client handler.
  unfold is_authorized_payment_handler.
  split; intro H.
  - apply Z.eqb_eq in H. exact H.
  - apply Z.eqb_eq. exact H.
Qed.
