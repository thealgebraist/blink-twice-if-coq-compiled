Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Payment Request Show User Gesture Semantics *)
(** Payment Request API §5.2 show() user activation requirement *)

Definition can_show_payment_request (has_user_activation : bool) (already_showing : bool) : bool :=
  has_user_activation && negb already_showing.

Theorem show_requires_activation_and_not_showing : forall act show,
  can_show_payment_request act show = true ->
  act = true /\ show = false.
Proof.
  intros act show H.
  unfold can_show_payment_request in H.
  apply andb_prop in H.
  destruct H as [Hact Hnshow].
  apply negb_true_iff in Hnshow.
  split; assumption.
Qed.
