Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Snap Stop Semantics *)
(** CSS Scroll Snap 1 §6.2: stop always boundary clamping *)

Definition stop_always_advance (curr next_snap : Z) : Z :=
  if curr <? next_snap then curr + 1
  else if curr >? next_snap then curr - 1
  else curr.

Theorem stop_always_advances_towards_target : forall curr next_snap,
  curr < next_snap ->
  curr < stop_always_advance curr next_snap <= next_snap.
Proof.
  intros curr next_snap Hlt.
  unfold stop_always_advance.
  assert (curr <? next_snap = true) by (apply Z.ltb_lt; lia).
  rewrite H.
  lia.
Qed.
