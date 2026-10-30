Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink performance.now() Monotonicity Semantics *)
(** High Resolution Time §4: strictly monotonic time advance *)

Definition advance_perf_time (current_time delta : Z) : Z :=
  current_time + Z.max 0 delta.

Theorem perf_time_monotonic : forall t d,
  t <= advance_perf_time t d.
Proof.
  intros t d.
  unfold advance_perf_time.
  assert (0 <= Z.max 0 d) by apply Z.le_max_l.
  lia.
Qed.

Theorem perf_time_strictly_advances : forall t d,
  0 < d ->
  t < advance_perf_time t d.
Proof.
  intros t d Hd.
  unfold advance_perf_time.
  assert (Z.max 0 d = d) by lia.
  rewrite H.
  lia.
Qed.
