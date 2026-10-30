Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC Statistics Timestamp Monotonicity Semantics *)
(** WebRTC Statistics API §4: timestamp non-decreasing progression *)

Definition advance_stats_time (curr_time delta : Z) : Z :=
  curr_time + Z.max 0 delta.

Theorem stats_timestamp_monotonic : forall t d,
  t <= advance_stats_time t d.
Proof.
  intros t d.
  unfold advance_stats_time.
  assert (0 <= Z.max 0 d) by apply Z.le_max_l.
  lia.
Qed.
