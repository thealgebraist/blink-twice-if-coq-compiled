Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Linear Easing Function Semantics *)
(** CSS Easing 2 §2: linear interpolation endpoints *)

Definition linear_lerp (v0 v1 t : Z) : Z :=
  v0 + (v1 - v0) * t / 1000.

Theorem linear_lerp_start : forall v0 v1,
  linear_lerp v0 v1 0 = v0.
Proof.
  intros v0 v1.
  unfold linear_lerp.
  rewrite Z.mul_0_r.
  change (0 / 1000) with 0.
  lia.
Qed.

Theorem linear_lerp_end : forall v0 v1,
  linear_lerp v0 v1 1000 = v1.
Proof.
  intros v0 v1.
  unfold linear_lerp.
  rewrite Z.div_mul by lia.
  lia.
Qed.
