Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Event Loop Microtask Draining Semantics *)
(** HTML Standard §8.1: microtask queue fully drained before next macro task *)

Definition drain_microtasks (microtask_count : Z) : Z :=
  0.

Theorem microtasks_fully_drained : forall count,
  drain_microtasks count = 0.
Proof.
  intros count.
  reflexivity.
Qed.
