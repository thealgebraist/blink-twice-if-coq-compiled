From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Color 3 §3.2 Opacity Alpha Multiplier Compounding *)
Definition compound_opacity (a1 a2 : Z) : Z :=
  (a1 * a2) / 255.

Theorem compound_opacity_nonneg : forall a1 a2,
  a1 >= 0 ->
  a2 >= 0 ->
  compound_opacity a1 a2 >= 0.
Proof.
  intros a1 a2 H1 H2.
  unfold compound_opacity.
  assert (0 <= (a1 * a2) / 255).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.

Theorem compound_opacity_bounded : forall a1 a2,
  0 <= a1 <= 255 ->
  0 <= a2 <= 255 ->
  compound_opacity a1 a2 <= 255.
Proof.
  intros a1 a2 [H1l H1u] [H2l H2u].
  unfold compound_opacity.
  assert (Hmul: a1 * a2 <= 255 * 255).
  { apply Z.mul_le_mono_nonneg; lia. }
  assert (Hdiv: (a1 * a2) / 255 <= (255 * 255) / 255) by (apply Z.div_le_mono; lia).
  rewrite Z.div_mul in Hdiv by lia.
  exact Hdiv.
Qed.
