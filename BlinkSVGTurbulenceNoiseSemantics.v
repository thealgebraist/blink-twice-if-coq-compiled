Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feTurbulence Noise Generation Semantics *)
(** Filter Effects 1 §13: feTurbulence pseudo-random bounds *)

Definition clamp_noise_to_byte (noise_val : Z) : Z :=
  Z.max 0 (Z.min 255 noise_val).

Theorem noise_to_byte_strictly_bounded : forall n,
  0 <= clamp_noise_to_byte n <= 255.
Proof.
  intros n.
  unfold clamp_noise_to_byte.
  lia.
Qed.

Theorem noise_valid_in_range_preserved : forall n,
  0 <= n <= 255 ->
  clamp_noise_to_byte n = n.
Proof.
  intros n Hn.
  unfold clamp_noise_to_byte.
  lia.
Qed.
