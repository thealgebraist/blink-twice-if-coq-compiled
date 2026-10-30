(******************************************************************************)
(* GeneralSpecificationSoundnessTheory.v                                      *)
(* Metatheory and General Soundness Proofs for the Bayesian-Guided             *)
(* Specification Synthesis (BGS-Spec) Framework.                              *)
(* Strictly 0 admits. Verified in Rocq/Coq 9.3.0.                             *)
(******************************************************************************)

Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(******************************************************************************)
(* 1. GENERAL CONSERVATION SOUNDNESS THEOREM                                  *)
(* Proves that for arbitrary discrete fractional partition kernels, the      *)
(* sum of allocated shares never exceeds total available resource W.          *)
(******************************************************************************)

Definition discrete_share (share total_shares available : Z) : Z :=
  (share * available) / total_shares.

Theorem general_conservation_soundness :
  forall (x y w : Z),
    0 <= x ->
    0 <= y ->
    0 < x + y ->
    0 <= w ->
    discrete_share x (x + y) w + discrete_share y (x + y) w <= w.
Proof.
  intros x y w Hx Hy Htot Hw.
  unfold discrete_share.
  assert (Hpos: 0 < x + y) by lia.
  assert (Hpos': x + y <> 0) by lia.
  pose proof (Z.div_mod (x * w) (x + y) Hpos') as Hdm1.
  pose proof (Z.div_mod (y * w) (x + y) Hpos') as Hdm2.
  pose proof (Z.mod_pos_bound (x * w) (x + y) Hpos) as Hmod1.
  pose proof (Z.mod_pos_bound (y * w) (x + y) Hpos) as Hmod2.
  assert (Hmult : (x + y) * (x * w / (x + y) + y * w / (x + y)) <= (x + y) * w).
  {
    assert (E: (x + y) * w = x * w + y * w) by ring.
    rewrite E, (Z.mul_add_distr_l (x + y)).
    rewrite (Z.mul_comm (x + y)) in Hdm1, Hdm2.
    lia.
  }
  nia.
Qed.

(******************************************************************************)
(* 2. GENERAL BOUNDING & CLAMPING SOUNDNESS THEOREM                           *)
(* Proves that the canonical clamp operator strictly enforces domain          *)
(* inclusion [lo, hi] for any arbitrary input value.                          *)
(******************************************************************************)

Definition canonical_clamp (v lo hi : Z) : Z :=
  if v <? lo then lo
  else if hi <? v then hi
  else v.

Theorem general_clamping_soundness :
  forall (v lo hi : Z),
    lo <= hi ->
    lo <= canonical_clamp v lo hi <= hi.
Proof.
  intros v lo hi Hle.
  unfold canonical_clamp.
  destruct (v <? lo) eqn:Elo.
  - apply Z.ltb_lt in Elo. lia.
  - apply Z.ltb_ge in Elo.
    destruct (hi <? v) eqn:Ehi.
    + apply Z.ltb_lt in Ehi. lia.
    + apply Z.ltb_ge in Ehi. lia.
Qed.

(******************************************************************************)
(* 3. GENERAL AFFINE INVOLUTION & BIJECTION THEOREM                           *)
(* Proves that reflective dual transformations parameterized by boundary C    *)
(* form an exact involution: T(T(x)) = x.                                     *)
(******************************************************************************)

Definition affine_reflect (bound x : Z) : Z := bound - x.

Theorem general_affine_involution_soundness :
  forall (bound x : Z),
    affine_reflect bound (affine_reflect bound x) = x.
Proof.
  intros bound x.
  unfold affine_reflect.
  ring.
Qed.

(******************************************************************************)
(* 4. GENERAL JOIN SEMI-LATTICE (BOUNDING BOX UNION) SOUNDNESS                *)
(* Proves Idempotence, Commutativity, and Associativity for coordinate-wise   *)
(* join operations.                                                           *)
(******************************************************************************)

Theorem general_join_idempotent :
  forall (a : Z), Z.max a a = a.
Proof.
  intros. apply Z.max_id.
Qed.

Theorem general_join_commutative :
  forall (a b : Z), Z.max a b = Z.max b a.
Proof.
  intros. apply Z.max_comm.
Qed.

Theorem general_join_associative :
  forall (a b c : Z), Z.max a (Z.max b c) = Z.max (Z.max a b) c.
Proof.
  intros. apply Z.max_assoc.
Qed.

(******************************************************************************)
(* 5. GENERAL ABSORBING PRIORITY DOMINANCE THEOREM                            *)
(* Proves that an absorbing priority element strictly dominates any bounded   *)
(* non-absorbing priority.                                                    *)
(******************************************************************************)

Definition priority_eval (is_top : bool) (weight : Z) : Z :=
  if is_top then 1000000 else weight.

Theorem general_absorbing_dominance_soundness :
  forall (w : Z),
    w < 1000000 ->
    priority_eval true 0 > priority_eval false w.
Proof.
  intros w Hw.
  unfold priority_eval.
  lia.
Qed.
