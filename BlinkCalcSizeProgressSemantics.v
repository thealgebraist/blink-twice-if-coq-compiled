(* =========================================================================
   BlinkCalcSizeProgressSemantics.v
   Formalization of Chromium Blink CSS calc-size() and progress() Evaluation
   Source: third_party/blink/renderer/core/css/css_math_expression_node.cc
           third_party/blink/renderer/core/css/css_calc_symbol_token.cc
   Specification: W3C CSS Values and Units Module Level 4 §10.1 & §10.6
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

(* 26.6 Fixed-Point Saturation Constants *)
Definition kInt32Min : Z := -2147483648.
Definition kInt32Max : Z := 2147483647.

Definition sat_clamp (x : Z) : Z :=
  if x <? kInt32Min then kInt32Min
  else if x >? kInt32Max then kInt32Max
  else x.

Inductive CalcSizeBasis : Type :=
  | BasisAny
  | BasisAuto (val : Z)
  | BasisMinContent (val : Z)
  | BasisMaxContent (val : Z)
  | BasisFitContent (val : Z)
  | BasisLength (val : Z).

Definition resolve_calc_size_basis (b : CalcSizeBasis) : Z :=
  match b with
  | BasisAny => 0
  | BasisAuto v => v
  | BasisMinContent v => v
  | BasisMaxContent v => v
  | BasisFitContent v => v
  | BasisLength v => v
  end.

Inductive CalcSizeExpr : Type :=
  | CS_SizeSymbol
  | CS_Literal (n : Z)
  | CS_Add (e1 e2 : CalcSizeExpr)
  | CS_Sub (e1 e2 : CalcSizeExpr)
  | CS_Mul (e : CalcSizeExpr) (k : Z).

Fixpoint eval_calc_size (basis_val : Z) (e : CalcSizeExpr) : Z :=
  match e with
  | CS_SizeSymbol => basis_val
  | CS_Literal n => sat_clamp n
  | CS_Add e1 e2 => sat_clamp (eval_calc_size basis_val e1 + eval_calc_size basis_val e2)
  | CS_Sub e1 e2 => sat_clamp (eval_calc_size basis_val e1 - eval_calc_size basis_val e2)
  | CS_Mul e1 k => sat_clamp (eval_calc_size basis_val e1 * k)
  end.

(* Progress fixed-point evaluation with scale 1000 *)
Definition eval_progress_scaled (val : Z) (start_pt : Z) (end_pt : Z) : Z :=
  let delta := end_pt - start_pt in
  if delta =? 0 then 0
  else sat_clamp (((val - start_pt) * 1000) / delta).

Theorem eval_calc_size_deterministic :
  forall basis_val e v1 v2,
    v1 = eval_calc_size basis_val e ->
    v2 = eval_calc_size basis_val e ->
    v1 = v2.
Proof.
  intros basis_val e v1 v2 H1 H2.
  subst. reflexivity.
Qed.

Theorem calc_size_symbol_evaluates_to_basis :
  forall basis_val,
    eval_calc_size basis_val CS_SizeSymbol = basis_val.
Proof.
  intros basis_val.
  simpl. reflexivity.
Qed.

Theorem eval_progress_at_start :
  forall start_pt end_pt,
    start_pt < end_pt ->
    eval_progress_scaled start_pt start_pt end_pt = 0.
Proof.
  intros start_pt end_pt Hlt.
  unfold eval_progress_scaled.
  assert (Hneq : end_pt - start_pt =? 0 = false).
  { apply Z.eqb_neq. lia. }
  rewrite Hneq.
  replace ((start_pt - start_pt) * 1000) with 0 by lia.
  rewrite Z.div_0_l by lia.
  unfold sat_clamp.
  unfold kInt32Min, kInt32Max.
  reflexivity.
Qed.

Theorem eval_progress_at_end :
  forall start_pt end_pt,
    start_pt < end_pt ->
    eval_progress_scaled end_pt start_pt end_pt = 1000.
Proof.
  intros start_pt end_pt Hlt.
  unfold eval_progress_scaled.
  assert (Hneq : end_pt - start_pt =? 0 = false).
  { apply Z.eqb_neq. lia. }
  rewrite Hneq.
  assert (Hpos : end_pt - start_pt > 0) by lia.
  replace ((end_pt - start_pt) * 1000) with (1000 * (end_pt - start_pt)) by lia.
  rewrite Z.div_mul by lia.
  unfold sat_clamp.
  unfold kInt32Min, kInt32Max.
  reflexivity.
Qed.

