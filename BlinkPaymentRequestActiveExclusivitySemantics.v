Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Payment Request Active Exclusivity Semantics *)
(** Payment Request API §5.2 at most one active request *)

Record payment_context_state : Type := mk_context {
  active_requests : Z
}.

Definition activate_request (s : payment_context_state) : option payment_context_state :=
  if active_requests s =? 0 then
    Some {| active_requests := 1 |}
  else
    None.

Theorem activate_request_preserves_exclusivity : forall s s',
  activate_request s = Some s' ->
  active_requests s' = 1.
Proof.
  intros s s' H.
  unfold activate_request in H.
  destruct (active_requests s =? 0) eqn:E; [injection H as H' | discriminate].
  rewrite <- H'.
  reflexivity.
Qed.
