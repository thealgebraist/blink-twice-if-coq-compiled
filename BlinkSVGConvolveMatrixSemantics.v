Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feConvolveMatrix Normalization Semantics *)
(** Filter Effects 1 §17: Divisor normalization and clamping *)

Definition convolve_normalize (sum_kernel explicit_divisor : Z) : Z :=
  if explicit_divisor =? 0 then
    if sum_kernel =? 0 then 1 else sum_kernel
  else explicit_divisor.

Definition convolve_pixel (sum_val divisor : Z) : Z :=
  let d := if divisor =? 0 then 1 else divisor in
  Z.max 0 (Z.min 255 (sum_val / d)).

Theorem convolve_pixel_bounded : forall sum_val divisor,
  0 <= convolve_pixel sum_val divisor <= 255.
Proof.
  intros sum_val divisor.
  unfold convolve_pixel.
  lia.
Qed.

Theorem convolve_zero_divisor_fallback_nonzero : forall s,
  0 < s ->
  convolve_normalize s 0 = s.
Proof.
  intros s Hs.
  unfold convolve_normalize; simpl.
  destruct (s =? 0) eqn:Heq.
  - apply Z.eqb_eq in Heq; lia.
  - reflexivity.
Qed.
