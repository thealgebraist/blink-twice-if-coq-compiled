Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Payment Request CanMakePayment Determinism Semantics *)
(** Payment Request API §5.3 canMakePayment() query determinism *)

Record payment_request_state : Type := mk_state {
  state_supported_methods : list Z;
  state_has_active_prompt : bool
}.

Definition can_make_payment_query (s : payment_request_state) (supported : bool)
  : bool * payment_request_state :=
  (supported, s).

Theorem can_make_payment_pure : forall s supp,
  snd (can_make_payment_query s supp) = s.
Proof.
  intros s supp.
  unfold can_make_payment_query.
  simpl.
  reflexivity.
Qed.
