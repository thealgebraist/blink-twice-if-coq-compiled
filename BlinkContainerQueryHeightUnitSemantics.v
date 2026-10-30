Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Container Query Height Unit cqh Semantics *)
(** CSS Containment 3 §3: 1cqh = 1% container height *)

Definition resolve_cqh (container_height n_units : Z) : Z :=
  (container_height * n_units) / 100.

Theorem cqh_zero_units_is_zero : forall ch,
  resolve_cqh ch 0 = 0.
Proof.
  intros ch.
  unfold resolve_cqh.
  rewrite Z.mul_0_r; reflexivity.
Qed.

Theorem cqh_monotonic_in_units : forall ch u1 u2,
  0 <= ch ->
  0 <= u1 ->
  u1 <= u2 ->
  resolve_cqh ch u1 <= resolve_cqh ch u2.
Proof.
  intros ch u1 u2 Hch Hu1 Hle.
  unfold resolve_cqh.
  apply Z.div_le_mono; [lia |].
  apply Z.mul_le_mono_nonneg_l; [exact Hch | exact Hle].
Qed.
