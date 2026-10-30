Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Table Collapsed Border Conflict Resolution Semantics *)
(** CSS 2.1 §17.6.2.1: border conflict resolution *)

Record collapsed_border : Type := mk_border {
  border_is_hidden : bool;
  border_width     : Z
}.

Definition border_wins (b1 b2 : collapsed_border) : bool :=
  if border_is_hidden b1 then true
  else if border_is_hidden b2 then false
  else border_width b2 <=? border_width b1.

Theorem hidden_border_always_wins : forall b1 b2,
  border_is_hidden b1 = true ->
  border_wins b1 b2 = true.
Proof.
  intros b1 b2 Hhidden.
  unfold border_wins.
  rewrite Hhidden.
  reflexivity.
Qed.
