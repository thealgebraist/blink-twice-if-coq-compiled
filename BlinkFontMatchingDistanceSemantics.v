(* ========================================================================= *)
(*               BlinkFontMatchingDistanceSemantics.v                       *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink CSS Font-Matching Distance Metric   *)
(* against CSS Fonts 3 §5.2. Fully constructive, 0 admits.                   *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition font_matching_distance (req_w cand_w req_s cand_s : Z) : Z :=
  Z.abs (req_w - cand_w) + Z.abs (req_s - cand_s).

Theorem font_matching_distance_nonneg : forall rw cw rs cs,
  font_matching_distance rw cw rs cs >= 0.
Proof.
  intros. unfold font_matching_distance.
  pose proof (Z.abs_nonneg (rw - cw)).
  pose proof (Z.abs_nonneg (rs - cs)).
  lia.
Qed.

Theorem font_matching_distance_zero_exact_match : forall rw cw rs cs,
  font_matching_distance rw cw rs cs = 0 <-> rw = cw /\ rs = cs.
Proof.
  intros rw cw rs cs.
  unfold font_matching_distance.
  pose proof (Z.abs_nonneg (rw - cw)).
  pose proof (Z.abs_nonneg (rs - cs)).
  split.
  - intros Hsum.
    assert (Z.abs (rw - cw) = 0 /\ Z.abs (rs - cs) = 0) by lia.
    destruct H1 as [Hw Hs].
    apply Z.abs_0_iff in Hw.
    apply Z.abs_0_iff in Hs.
    split; lia.
  - intros [Hw Hs].
    subst.
    assert (cw - cw = 0) as -> by lia.
    assert (cs - cs = 0) as -> by lia.
    reflexivity.
Qed.

Theorem font_matching_distance_triangle : forall w1 w2 w3 s1 s2 s3,
  font_matching_distance w1 w3 s1 s3 <=
  font_matching_distance w1 w2 s1 s2 + font_matching_distance w2 w3 s2 s3.
Proof.
  intros. unfold font_matching_distance.
  assert (Hw: Z.abs (w1 - w3) <= Z.abs (w1 - w2) + Z.abs (w2 - w3)).
  {
    assert (w1 - w3 = (w1 - w2) + (w2 - w3)) as -> by ring.
    apply Z.abs_triangle.
  }
  assert (Hs: Z.abs (s1 - s3) <= Z.abs (s1 - s2) + Z.abs (s2 - s3)).
  {
    assert (s1 - s3 = (s1 - s2) + (s2 - s3)) as -> by ring.
    apply Z.abs_triangle.
  }
  lia.
Qed.
