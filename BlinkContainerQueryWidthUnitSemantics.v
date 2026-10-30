Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Container Query Width Unit cqw Semantics *)
(** CSS Containment 3 §3: 1cqw = 1% container width *)

Definition resolve_cqw (container_width n_units : Z) : Z :=
  (container_width * n_units) / 100.

Theorem cqw_zero_units_is_zero : forall cw,
  resolve_cqw cw 0 = 0.
Proof.
  intros cw.
  unfold resolve_cqw.
  rewrite Z.mul_0_r; reflexivity.
Qed.

Theorem cqw_monotonic_in_units : forall cw u1 u2,
  0 <= cw ->
  0 <= u1 ->
  u1 <= u2 ->
  resolve_cqw cw u1 <= resolve_cqw cw u2.
Proof.
  intros cw u1 u2 Hcw Hu1 Hle.
  unfold resolve_cqw.
  apply Z.div_le_mono; [lia |].
  apply Z.mul_le_mono_nonneg_l; [exact Hcw | exact Hle].
Qed.
