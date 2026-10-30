(**
  BlinkCSSMathCalcSemantics.v
  Formal specification of Chromium Blink CSS math expression AST simplification and clamping
  derived from third_party/blink/renderer/core/css/css_math_expression_node.cc
  according to W3C CSS Values and Units Module Level 4 (§10.2 & §10.3 Mathematical Expressions: calc, min, max, clamp).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. CSS Math Expression AST *)

Inductive CSSMathExpr : Type :=
  | MathLit (v : Z)
  | MathAdd (e1 e2 : CSSMathExpr)
  | MathSub (e1 e2 : CSSMathExpr)
  | MathMul (e1 e2 : CSSMathExpr)
  | MathMin (e1 e2 : CSSMathExpr)
  | MathMax (e1 e2 : CSSMathExpr)
  | MathClamp (e_min e_val e_max : CSSMathExpr).

Definition css_clamp (min_v val_v max_v : Z) : Z :=
  let effective_max := Z.max min_v max_v in
  Z.max min_v (Z.min val_v effective_max).

Fixpoint eval_math_expr (e : CSSMathExpr) : Z :=
  match e with
  | MathLit v => v
  | MathAdd e1 e2 => eval_math_expr e1 + eval_math_expr e2
  | MathSub e1 e2 => eval_math_expr e1 - eval_math_expr e2
  | MathMul e1 e2 => eval_math_expr e1 * eval_math_expr e2
  | MathMin e1 e2 => Z.min (eval_math_expr e1) (eval_math_expr e2)
  | MathMax e1 e2 => Z.max (eval_math_expr e1) (eval_math_expr e2)
  | MathClamp e_min e_val e_max =>
      css_clamp (eval_math_expr e_min) (eval_math_expr e_val) (eval_math_expr e_max)
  end.

(** 2. Clamp Invariant Theorems *)

Theorem css_clamp_satisfies_min_bound :
  forall min_v val_v max_v : Z,
    min_v <= css_clamp min_v val_v max_v.
Proof.
  intros min_v val_v max_v.
  unfold css_clamp.
  apply Z.le_max_l.
Qed.

Theorem css_clamp_satisfies_max_bound :
  forall min_v val_v max_v : Z,
    min_v <= max_v ->
    css_clamp min_v val_v max_v <= max_v.
Proof.
  intros min_v val_v max_v Hle.
  unfold css_clamp.
  assert (Z.max min_v max_v = max_v) by (apply Z.max_r; exact Hle).
  rewrite H.
  apply Z.max_lub.
  - exact Hle.
  - apply Z.le_min_r.
Qed.

Theorem css_clamp_idempotent :
  forall min_v val_v max_v : Z,
    min_v <= max_v ->
    css_clamp min_v (css_clamp min_v val_v max_v) max_v = css_clamp min_v val_v max_v.
Proof.
  intros min_v val_v max_v Hle.
  unfold css_clamp.
  assert (Z.max min_v max_v = max_v) by (apply Z.max_r; exact Hle).
  rewrite H.
  lia.
Qed.

(** 3. Expression Algebraic Properties *)

Theorem math_add_comm :
  forall e1 e2 : CSSMathExpr,
    eval_math_expr (MathAdd e1 e2) = eval_math_expr (MathAdd e2 e1).
Proof.
  intros e1 e2.
  simpl. lia.
Qed.

Theorem math_add_assoc :
  forall e1 e2 e3 : CSSMathExpr,
    eval_math_expr (MathAdd (MathAdd e1 e2) e3) = eval_math_expr (MathAdd e1 (MathAdd e2 e3)).
Proof.
  intros e1 e2 e3.
  simpl. lia.
Qed.

Theorem math_min_comm :
  forall e1 e2 : CSSMathExpr,
    eval_math_expr (MathMin e1 e2) = eval_math_expr (MathMin e2 e1).
Proof.
  intros e1 e2.
  simpl. apply Z.min_comm.
Qed.

Theorem math_max_comm :
  forall e1 e2 : CSSMathExpr,
    eval_math_expr (MathMax e1 e2) = eval_math_expr (MathMax e2 e1).
Proof.
  intros e1 e2.
  simpl. apply Z.max_comm.
Qed.

Theorem math_mul_distr_add :
  forall e1 e2 e3 : CSSMathExpr,
    eval_math_expr (MathMul e1 (MathAdd e2 e3)) =
    eval_math_expr (MathAdd (MathMul e1 e2) (MathMul e1 e3)).
Proof.
  intros e1 e2 e3.
  simpl. ring.
Qed.

