Require Import ZArith.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Notification Tag Replacement Semantics *)
(** Notifications API §4.2: tag replacement replaces existing notification *)

Fixpoint replace_or_append (tag : Z) (val : Z) (l : list (Z * Z)) : list (Z * Z) :=
  match l with
  | [] => [(tag, val)]
  | (t, v) :: rest =>
      if tag =? t then (tag, val) :: rest
      else (t, v) :: replace_or_append tag val rest
  end.

Theorem tag_replacement_head : forall tag val v rest,
  replace_or_append tag val ((tag, v) :: rest) = (tag, val) :: rest.
Proof.
  intros tag val v rest.
  simpl.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.
