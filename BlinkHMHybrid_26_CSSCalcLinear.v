(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSCalcLinear := mkCSSCalcLinear {
  csscalclinear_px_term : Z;
  csscalclinear_pct_num : Z
}.

Definition eval_calc_linear_pct (px_term : Z) (pct_num : Z) (basis : Z) : Z :=
  px_term + (basis * pct_num) / 100.

Theorem eval_calc_linear_zero_pct_identity :
  forall (px_term basis : Z), eval_calc_linear_pct px_term 0 basis = px_term.
Proof.
  intros px_term basis.
  unfold eval_calc_linear_pct.
  rewrite Z.mul_0_r, Z.div_0_l by lia.
  lia.
Qed.
