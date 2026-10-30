Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Keyframe Timing Delay Semantics *)
(** Web Animations §5.3.4: active interval non-negativity *)

Definition compute_active_interval (total_duration delay : Z) : Z :=
  Z.max 0 (total_duration - delay).

Theorem active_interval_nonneg : forall total delay,
  0 <= compute_active_interval total delay.
Proof.
  intros total delay.
  unfold compute_active_interval.
  lia.
Qed.

Theorem zero_delay_full_interval : forall total,
  0 <= total ->
  compute_active_interval total 0 = total.
Proof.
  intros total Ht.
  unfold compute_active_interval.
  lia.
Qed.
