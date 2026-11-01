(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSMathClamp := mkCSSMathClamp {
  cssmathclamp_min_val : Z;
  cssmathclamp_preferred_val : Z;
  cssmathclamp_max_val : Z
}.

Definition css_clamp_val (lo : Z) (val : Z) (hi : Z) : Z :=
  Z.max lo (Z.min val hi).

Theorem css_clamp_bounds_and_min_wins :
  forall (lo val hi : Z), (lo <= hi -> lo <= css_clamp_val lo val hi <= hi) /\ (hi < lo -> css_clamp_val lo val hi = lo).
Proof.
  intros lo val hi. unfold css_clamp_val. lia.
Qed.
