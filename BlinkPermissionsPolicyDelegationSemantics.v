Require Import Bool.

(** * Blink Permissions Policy Delegation Semantics *)
(** Permissions Policy §4: delegation to iframe requires parent allow + allow attribute *)

Definition permission_allowed_in_iframe (parent_allowed : bool) (declared_in_allow : bool) : bool :=
  parent_allowed && declared_in_allow.

Theorem permission_delegation_sound : forall p a,
  permission_allowed_in_iframe p a = true ->
  p = true /\ a = true.
Proof.
  intros p a H.
  unfold permission_allowed_in_iframe in H.
  apply andb_prop in H.
  exact H.
Qed.

Theorem permission_denied_without_parent : forall a,
  permission_allowed_in_iframe false a = false.
Proof.
  intros a. reflexivity.
Qed.
