Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink PerformanceObserver Buffer Bounds Semantics *)
(** Performance Timeline §3: buffer capacity bounding and overflow dropping *)

Definition store_performance_entry (current_count max_buffer_size : Z) : Z :=
  if current_count <? max_buffer_size then current_count + 1
  else current_count.

Theorem observer_buffer_bounded : forall c max_sz,
  0 <= c <= max_sz ->
  store_performance_entry c max_sz <= max_sz.
Proof.
  intros c max_sz Hbounds.
  unfold store_performance_entry.
  destruct (c <? max_sz) eqn:Heq.
  - apply Z.ltb_lt in Heq. lia.
  - lia.
Qed.
