Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink AudioParam Timeline Ramping Semantics *)
(** Web Audio API 1 §2: linear interpolation endpoint exactness *)

Definition ramp_value (v0 v1 t total : Z) : Z :=
  v0 + ((v1 - v0) * t) / total.

Theorem ramp_start : forall v0 v1 tot,
  0 < tot ->
  ramp_value v0 v1 0 tot = v0.
Proof.
  intros v0 v1 tot Htot.
  unfold ramp_value.
  replace ((v1 - v0) * 0) with 0 by ring.
  rewrite Z.div_0_l by lia.
  lia.
Qed.

Theorem ramp_end : forall v0 v1 tot,
  0 < tot ->
  ramp_value v0 v1 tot tot = v1.
Proof.
  intros v0 v1 tot Htot.
  unfold ramp_value.
  rewrite Z.div_mul by lia.
  lia.
Qed.
