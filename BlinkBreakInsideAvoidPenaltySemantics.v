Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Break Inside Avoid Penalty Semantics *)
(** CSS Fragmentation 3 §3.3: avoid penalty maximization *)

Definition compute_break_penalty (avoid_break : bool) : Z :=
  if avoid_break then 100000
  else 0.

Theorem avoid_penalty_strictly_greater :
  compute_break_penalty false < compute_break_penalty true.
Proof.
  unfold compute_break_penalty; lia.
Qed.
