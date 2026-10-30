Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feComposite Arithmetic Mode Semantics *)
(** Filter Effects 1 §12: feComposite arithmetic clamping *)

Definition clamp_channel (val : Z) : Z :=
  Z.max 0 (Z.min 255 val).

Definition composite_arithmetic_unclamped (k1 k2 k3 k4 i1 i2 : Z) : Z :=
  k1 * i1 * i2 / 255 + k2 * i1 + k3 * i2 + k4.

Definition composite_arithmetic (k1 k2 k3 k4 i1 i2 : Z) : Z :=
  clamp_channel (composite_arithmetic_unclamped k1 k2 k3 k4 i1 i2).

Theorem composite_arithmetic_in_bounds : forall k1 k2 k3 k4 i1 i2,
  0 <= composite_arithmetic k1 k2 k3 k4 i1 i2 <= 255.
Proof.
  intros k1 k2 k3 k4 i1 i2.
  unfold composite_arithmetic, clamp_channel.
  lia.
Qed.

Theorem clamp_channel_idempotent : forall v,
  clamp_channel (clamp_channel v) = clamp_channel v.
Proof.
  intros v.
  unfold clamp_channel.
  lia.
Qed.
