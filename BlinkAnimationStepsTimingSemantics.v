Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Steps Timing Function Semantics *)
(** CSS Easing 1 §3.2: steps(n) discrete index calculation *)

Definition eval_steps_jump_end (t n : Z) : Z :=
  if n <=? 0 then 0
  else Z.max 0 (Z.min (n - 1) ((t * n) / 1000)).

Theorem steps_jump_end_bounded : forall t n,
  0 < n ->
  0 <= eval_steps_jump_end t n < n.
Proof.
  intros t n Hn.
  unfold eval_steps_jump_end.
  destruct (n <=? 0) eqn:Hle; [lia |].
  lia.
Qed.
