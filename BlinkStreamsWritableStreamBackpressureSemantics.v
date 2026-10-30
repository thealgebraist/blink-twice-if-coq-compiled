Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Streams WritableStream Backpressure Semantics *)
(** Streams Standard §4.2: desired_size = high_water_mark - queue_size; backpressure <= 0 *)

Definition desired_size (high_water_mark queue_size : Z) : Z :=
  high_water_mark - queue_size.

Definition has_backpressure (high_water_mark queue_size : Z) : bool :=
  desired_size high_water_mark queue_size <=? 0.

Theorem backpressure_when_full_or_overflow : forall hwm q,
  hwm <= q ->
  has_backpressure hwm q = true.
Proof.
  intros hwm q Hle.
  unfold has_backpressure, desired_size.
  apply Z.leb_le.
  lia.
Qed.

Theorem no_backpressure_when_under_capacity : forall hwm q,
  q < hwm ->
  has_backpressure hwm q = false.
Proof.
  intros hwm q Hlt.
  unfold has_backpressure, desired_size.
  apply Z.leb_gt.
  lia.
Qed.
