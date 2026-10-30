(* Blink2Coq Synthesis for FlexibleBoxAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem flex_space_conservation : forall g1 g2 fr,
  0 <= g1 -> 0 <= g2 -> 0 < g1 + g2 -> 0 <= fr ->
  g1 * fr / (g1 + g2) + g2 * fr / (g1 + g2) <= fr.
Proof.
  intros g1 g2 fr H1 H2 Htot Hfr.
  assert (Hpos: 0 < g1 + g2) by lia.
  assert (Hpos': g1 + g2 <> 0) by lia.
  pose proof (Z.div_mod (g1 * fr) (g1 + g2) Hpos') as Hdm1.
  pose proof (Z.div_mod (g2 * fr) (g1 + g2) Hpos') as Hdm2.
  pose proof (Z.mod_pos_bound (g1 * fr) (g1 + g2) Hpos) as Hmod1.
  pose proof (Z.mod_pos_bound (g2 * fr) (g1 + g2) Hpos) as Hmod2.
  assert (Hmult : (g1 + g2) * (g1 * fr / (g1 + g2) + g2 * fr / (g1 + g2)) <= (g1 + g2) * fr).
  {
    assert (E: (g1 + g2) * fr = g1 * fr + g2 * fr) by ring.
    rewrite E, (Z.mul_add_distr_l (g1 + g2)).
    rewrite (Z.mul_comm (g1 + g2)) in Hdm1, Hdm2. lia.
  }
  nia.
Qed.
