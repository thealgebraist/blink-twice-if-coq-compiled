From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Color 4 §13 Alpha Compositing (Porter-Duff Source Over) *)
Definition alpha_composite_over (a_src : Z) (a_dst : Z) : Z :=
  a_src + (a_dst * (255 - a_src)) / 255.

Theorem alpha_composite_opaque_source : forall a_dst,
  alpha_composite_over 255 a_dst = 255.
Proof.
  intros a_dst.
  unfold alpha_composite_over.
  replace (255 - 255) with 0 by lia.
  rewrite Z.mul_0_r.
  rewrite Z.div_0_l by lia.
  lia.
Qed.

Theorem alpha_composite_nonneg : forall a_src a_dst,
  0 <= a_src <= 255 ->
  0 <= a_dst <= 255 ->
  alpha_composite_over a_src a_dst >= 0.
Proof.
  intros a_src a_dst [Hs1 Hs2] [Hd1 Hd2].
  unfold alpha_composite_over.
  assert (0 <= a_dst * (255 - a_src)) by (apply Z.mul_nonneg_nonneg; lia).
  assert (0 <= (a_dst * (255 - a_src)) / 255) by (apply Z.div_le_lower_bound; lia).
  lia.
Qed.
