(* Blink2Coq Synthesis for BoxShape *)
(* Source: third_party/blink/renderer/core/layout/shapes/box_shape.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem inset_corner_radius_scaled_bounded : forall r1 r2 w,
  0 <= r1 -> 0 <= r2 -> 0 < r1 + r2 -> 0 <= w ->
  r1 * w / (r1 + r2) + r2 * w / (r1 + r2) <= w.
Proof.
  intros r1 r2 w H1 H2 Htot Hw.
  assert (Hpos: 0 < r1 + r2) by lia.
  assert (Hpos': r1 + r2 <> 0) by lia.
  pose proof (Z.div_mod (r1 * w) (r1 + r2) Hpos') as Hdm1.
  pose proof (Z.div_mod (r2 * w) (r1 + r2) Hpos') as Hdm2.
  pose proof (Z.mod_pos_bound (r1 * w) (r1 + r2) Hpos) as Hmod1.
  pose proof (Z.mod_pos_bound (r2 * w) (r1 + r2) Hpos) as Hmod2.
  assert (Hmult : (r1 + r2) * (r1 * w / (r1 + r2) + r2 * w / (r1 + r2)) <= (r1 + r2) * w).
  {
    assert (E: (r1 + r2) * w = r1 * w + r2 * w) by ring.
    rewrite E, (Z.mul_add_distr_l (r1 + r2)).
    rewrite (Z.mul_comm (r1 + r2)) in Hdm1, Hdm2. lia.
  }
  nia.
Qed.
