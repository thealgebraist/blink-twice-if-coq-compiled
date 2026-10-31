(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSBoxShorthand := mkCSSBoxShorthand {
  cssboxshorthand_top : Z;
  cssboxshorthand_right : Z;
  cssboxshorthand_bottom : Z;
  cssboxshorthand_left : Z
}.

Definition shorthand_axis_sum (n_vals : Z) (v1 : Z) (v2 : Z) : Z :=
  if n_vals =? 1 then v1 + v1 else v2 + v2.

Theorem shorthand_axis_sum_even_nonneg :
  forall (n_vals v1 v2 : Z), 0 <= v1 -> 0 <= v2 -> 0 <= shorthand_axis_sum n_vals v1 v2.
Proof.
  intros n_vals v1 v2 Hv1 Hv2.
  unfold shorthand_axis_sum.
  destruct (n_vals =? 1); lia.
Qed.
