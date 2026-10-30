Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Active Duration Monotonicity Semantics *)
(** Web Animations §5.3.7: active duration monotonicity *)

Definition compute_active_duration (iteration_duration iteration_count : Z) : Z :=
  Z.max 0 iteration_duration * Z.max 0 iteration_count.

Theorem active_duration_monotonic : forall dur c1 c2,
  0 <= dur ->
  0 <= c1 <= c2 ->
  compute_active_duration dur c1 <= compute_active_duration dur c2.
Proof.
  intros dur c1 c2 Hdur [Hc1 Hc2].
  unfold compute_active_duration.
  assert (Z.max 0 dur = dur) by lia.
  assert (Z.max 0 c1 = c1) by lia.
  assert (Z.max 0 c2 = c2) by lia.
  rewrite H, H0, H1.
  apply Z.mul_le_mono_nonneg_l; lia.
Qed.
