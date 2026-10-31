(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSCustomPropEnv := mkCSSCustomPropEnv {
  csscustompropenv_var_depth : Z;
  csscustompropenv_max_depth : Z;
  csscustompropenv_has_fallback : bool
}.

Definition consume_var_fuel (fuel : Z) : Z :=
  if fuel <=? 0 then 0 else fuel - 1.

Theorem consume_var_fuel_strict_decrease :
  forall (fuel : Z), 0 < fuel -> 0 <= consume_var_fuel fuel < fuel.
Proof.
  intros fuel Hpos.
  unfold consume_var_fuel.
  destruct (fuel <=? 0) eqn:E.
  - apply Z.leb_le in E. lia.
  - lia.
Qed.
