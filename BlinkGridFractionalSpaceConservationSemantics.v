Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Grid Fractional Space Conservation Semantics *)
(** CSS Grid Layout 1 §11.7.1: find the size of an fr *)

Definition compute_fr_share (fr_weight total_fr avail : Z) : Z :=
  (fr_weight * avail) / total_fr.

Theorem fr_shares_conservation_two_tracks : forall fr1 fr2 avail,
  0 <= fr1 ->
  0 <= fr2 ->
  0 < fr1 + fr2 ->
  avail >= 0 ->
  compute_fr_share fr1 (fr1 + fr2) avail + compute_fr_share fr2 (fr1 + fr2) avail <= avail.
Proof.
  intros fr1 fr2 avail H1 H2 Htot Havail.
  unfold compute_fr_share.
  assert (Hpos' : fr1 + fr2 <> 0) by lia.
  assert (Hpos : 0 < fr1 + fr2) by lia.
  pose proof (Z.div_mod (fr1 * avail) (fr1 + fr2) Hpos') as Hdm1.
  pose proof (Z.div_mod (fr2 * avail) (fr1 + fr2) Hpos') as Hdm2.
  pose proof (Z.mod_pos_bound (fr1 * avail) (fr1 + fr2) Hpos) as Hmod1.
  pose proof (Z.mod_pos_bound (fr2 * avail) (fr1 + fr2) Hpos) as Hmod2.
  assert (Hmult : (fr1 + fr2) * (fr1 * avail / (fr1 + fr2) + fr2 * avail / (fr1 + fr2)) <= (fr1 + fr2) * avail).
  {
    assert (E: (fr1 + fr2) * avail = fr1 * avail + fr2 * avail) by ring.
    rewrite E.
    rewrite (Z.mul_add_distr_l (fr1 + fr2)).
    rewrite (Z.mul_comm (fr1 + fr2) (fr1 * avail / (fr1 + fr2))) in Hdm1.
    rewrite (Z.mul_comm (fr1 + fr2) (fr2 * avail / (fr1 + fr2))) in Hdm2.
    lia.
  }
  nia.
Qed.
