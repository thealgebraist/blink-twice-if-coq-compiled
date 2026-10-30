(* Blink2Coq HTML/CSS Synthesis for ElementRuleCollector *)
(* Source: renderer/core/css/element_rule_collector.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition rule_priority (is_important : bool) (spec : Z) : Z :=
  if is_important then 10000000 + spec else spec.
Theorem important_rule_dominates : forall s_norm s_imp,
  0 <= s_norm < 1000000 -> 0 <= s_imp ->
  rule_priority false s_norm < rule_priority true s_imp.
Proof. intros. unfold rule_priority. lia. Qed.
