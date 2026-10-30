From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.4 Min-Size Overrides Max-Size *)
Definition resolve_min_max_clamping (min_size : Z) (max_size : Z) (target : Z) : Z :=
  Z.max min_size (Z.min max_size target).

Theorem min_size_unconditionally_respected : forall min_s max_s target,
  resolve_min_max_clamping min_s max_s target >= min_s.
Proof.
  intros. unfold resolve_min_max_clamping.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem max_size_respected_when_consistent : forall min_s max_s target,
  min_s <= max_s ->
  resolve_min_max_clamping min_s max_s target <= max_s.
Proof.
  intros min_s max_s target Hle.
  unfold resolve_min_max_clamping.
  assert (Z.min max_s target <= max_s) by (apply Z.le_min_l).
  destruct (Z.max_dec min_s (Z.min max_s target)); lia.
Qed.
