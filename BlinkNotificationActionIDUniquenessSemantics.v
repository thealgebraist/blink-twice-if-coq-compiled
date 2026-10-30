Require Import ZArith.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Notification Action ID Uniqueness Semantics *)
(** Notifications API §4.1: NotificationAction.action identifier uniqueness *)

Fixpoint action_exists (id : Z) (l : list Z) : bool :=
  match l with
  | [] => false
  | x :: xs => if id =? x then true else action_exists id xs
  end.

Definition add_action (id : Z) (l : list Z) : option (list Z) :=
  if action_exists id l then None else Some (id :: l).

Theorem add_action_uniqueness : forall id l,
  action_exists id l = false ->
  add_action id l = Some (id :: l).
Proof.
  intros id l H.
  unfold add_action.
  rewrite H.
  reflexivity.
Qed.
