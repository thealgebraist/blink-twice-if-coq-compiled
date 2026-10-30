Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feBlend Mode Semantics *)
(** Filter Effects 1 §11: feBlend multiply & screen modes *)

Definition blend_multiply (c1 c2 : Z) : Z :=
  (c1 * c2) / 255.

Definition blend_screen (c1 c2 : Z) : Z :=
  255 - ((255 - c1) * (255 - c2)) / 255.

Theorem multiply_mode_bounded : forall c1 c2,
  0 <= c1 <= 255 ->
  0 <= c2 <= 255 ->
  0 <= blend_multiply c1 c2 <= 255.
Proof.
  intros c1 c2 H1 H2.
  unfold blend_multiply.
  assert (0 <= c1 * c2) by (apply Z.mul_nonneg_nonneg; lia).
  assert (c1 * c2 <= 255 * 255) by (apply Z.mul_le_mono_nonneg; lia).
  split.
  - apply Z.div_le_lower_bound; lia.
  - apply Z.div_le_upper_bound; lia.
Qed.

Theorem screen_mode_bounded : forall c1 c2,
  0 <= c1 <= 255 ->
  0 <= c2 <= 255 ->
  0 <= blend_screen c1 c2 <= 255.
Proof.
  intros c1 c2 H1 H2.
  unfold blend_screen.
  assert (0 <= 255 - c1 <= 255) by lia.
  assert (0 <= 255 - c2 <= 255) by lia.
  assert (0 <= (255 - c1) * (255 - c2)) by (apply Z.mul_nonneg_nonneg; lia).
  assert ((255 - c1) * (255 - c2) <= 255 * 255) by (apply Z.mul_le_mono_nonneg; lia).
  assert (0 <= ((255 - c1) * (255 - c2)) / 255) by (apply Z.div_le_lower_bound; lia).
  assert (((255 - c1) * (255 - c2)) / 255 <= 255) by (apply Z.div_le_upper_bound; lia).
  split; lia.
Qed.
