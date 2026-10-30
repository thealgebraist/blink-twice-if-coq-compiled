Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feGaussianBlur Kernel Spread Radius Semantics *)
(** Filter Effects 1 §8: feGaussianBlur stdDeviation bounds *)

Definition stddev_to_kernel_radius (std_dev : Z) : Z :=
  if std_dev <=? 0 then 0
  else (3 * std_dev + 1) / 2.

Definition blur_outset_dimension (size r : Z) : Z :=
  size + 2 * r.

Theorem kernel_radius_nonneg : forall std_dev,
  0 <= std_dev ->
  0 <= stddev_to_kernel_radius std_dev.
Proof.
  intros std_dev Hsd.
  unfold stddev_to_kernel_radius.
  destruct (std_dev <=? 0) eqn:Heq.
  - lia.
  - apply Z.leb_gt in Heq.
    assert (0 <= (3 * std_dev + 1) / 2) by (apply Z.div_le_lower_bound; lia).
    lia.
Qed.

Theorem blur_outset_monotonic : forall size r,
  0 <= size ->
  0 <= r ->
  size <= blur_outset_dimension size r.
Proof.
  intros size r Hsize Hr.
  unfold blur_outset_dimension.
  lia.
Qed.
