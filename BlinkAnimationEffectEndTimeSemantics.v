Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Effect End Time Calculation Semantics *)
(** Web Animations §5.3.8: end time calculation *)

Definition compute_effect_end_time (start_delay active_duration : Z) : Z :=
  Z.max 0 (start_delay + Z.max 0 active_duration).

Theorem effect_end_time_nonneg : forall delay active,
  0 <= compute_effect_end_time delay active.
Proof.
  intros delay active.
  unfold compute_effect_end_time.
  lia.
Qed.

Theorem zero_delay_end_time_equals_active : forall active,
  0 <= active ->
  compute_effect_end_time 0 active = active.
Proof.
  intros active Ha.
  unfold compute_effect_end_time.
  lia.
Qed.
