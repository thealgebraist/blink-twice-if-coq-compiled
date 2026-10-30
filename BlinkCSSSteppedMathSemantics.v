(** * BlinkCSSSteppedMathSemantics.v
    Formalization of Chromium Blink CSS Values and Units Level 4 §10.4
    Stepped Value Functions: round(), mod(), and rem().
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.

Open Scope Z_scope.

(** ** 1. AST and Operator Definitions *)

Inductive RoundingStrategy : Type :=
  | Nearest
  | Up
  | Down
  | ToZero.

Inductive CSSMathOperator : Type :=
  | kRound (s : RoundingStrategy)
  | kMod
  | kRem.

(** ** 2. Evaluation Functions *)

Definition eval_mod (a b : Z) : Z :=
  let step := Z.abs b in
  if step =? 0 then 0
  else a mod step.

Definition eval_rem (a b : Z) : Z :=
  let step := Z.abs b in
  if step =? 0 then 0
  else Z.rem a step.

Definition eval_round (s : RoundingStrategy) (a b : Z) : Z :=
  let step := Z.abs b in
  if step =? 0 then 0
  else
    match s with
    | Down => (a / step) * step
    | Up =>
        let r := a mod step in
        if r =? 0 then a
        else ((a / step) + 1) * step
    | ToZero => (Z.quot a step) * step
    | Nearest =>
        let r := a mod step in
        if r * 2 <? step then (a / step) * step
        else ((a / step) + 1) * step
    end.

(** ** 3. Mathematical Invariants & Verification *)

(** Invariant 1: Step Sign Invariance — round(s, a, b) = round(s, a, -b) *)
Theorem round_step_sign_invariant : forall s a b,
  eval_round s a b = eval_round s a (-b).
Proof.
  intros s a b.
  unfold eval_round.
  rewrite Z.abs_opp.
  reflexivity.
Qed.

(** Invariant 2: Euclidean Division Reconstruction for mod *)
Theorem mod_division_reconstruction : forall a b,
  b <> 0 ->
  a = (Z.abs b) * (a / Z.abs b) + eval_mod a b.
Proof.
  intros a b Hb.
  unfold eval_mod.
  assert (Hpos : Z.abs b > 0) by lia.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  apply Z.div_mod. lia.
Qed.

(** Invariant 3: Division Reconstruction for rem *)
Theorem rem_division_reconstruction : forall a b,
  b <> 0 ->
  a = (Z.abs b) * (Z.quot a (Z.abs b)) + eval_rem a b.
Proof.
  intros a b Hb.
  unfold eval_rem.
  assert (Hpos : Z.abs b > 0) by lia.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  apply Z.quot_rem'.
Qed.

(** Invariant 4: mod Bounds — 0 <= mod(a, b) < |b| *)
Theorem mod_bounds : forall a b,
  b <> 0 ->
  0 <= eval_mod a b < Z.abs b.
Proof.
  intros a b Hb.
  unfold eval_mod.
  assert (Hpos : Z.abs b > 0) by lia.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  apply Z.mod_pos_bound. lia.
Qed.

(** Invariant 5: round(Down, a, b) is an exact integer multiple of |b| *)
Theorem round_down_multiple : forall a b,
  b <> 0 -> exists k, eval_round Down a b = k * Z.abs b.
Proof.
  intros a b Hb.
  unfold eval_round.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  exists (a / Z.abs b).
  rewrite Z.mul_comm. reflexivity.
Qed.

(** Invariant 6: round(Up, a, b) is an exact integer multiple of |b| *)
Theorem round_up_multiple : forall a b,
  b <> 0 -> exists k, eval_round Up a b = k * Z.abs b.
Proof.
  intros a b Hb.
  unfold eval_round.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  destruct (a mod Z.abs b =? 0) eqn:Heq.
  - apply Z.eqb_eq in Heq.
    pose proof (Z.div_exact a (Z.abs b) (ltac:(lia))) as [_ Hrw].
    rewrite (Hrw Heq).
    exists (a / Z.abs b).
    rewrite Z.mul_comm. reflexivity.
  - exists ((a / Z.abs b) + 1).
    rewrite Z.mul_comm. reflexivity.
Qed.

(** Invariant 7: round(Down, a, b) <= a *)
Theorem round_down_le : forall a b,
  b <> 0 ->
  eval_round Down a b <= a.
Proof.
  intros a b Hb.
  unfold eval_round.
  assert (Hpos : Z.abs b > 0) by lia.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  rewrite Z.mul_comm.
  apply Z.mul_div_le. lia.
Qed.

(** Invariant 8: a <= round(Up, a, b) *)
Theorem round_up_ge : forall a b,
  b <> 0 ->
  a <= eval_round Up a b.
Proof.
  intros a b Hb.
  unfold eval_round.
  assert (Hpos : 0 < Z.abs b) by lia.
  assert (Hnz : (Z.abs b =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hnz.
  destruct (a mod Z.abs b =? 0) eqn:Heq.
  - lia.
  - apply Z.eqb_neq in Heq.
    pose proof (Z.mod_pos_bound a (Z.abs b) Hpos) as Hmod.
    pose proof (Z.div_mod a (Z.abs b) (ltac:(lia))) as Hdm.
    rewrite Z.mul_add_distr_r.
    rewrite Z.mul_1_l.
    lia.
Qed.
