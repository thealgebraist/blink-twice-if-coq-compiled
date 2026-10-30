(* Blink2Coq HTML/CSS Synthesis for CSSSelector *)
(* Source: renderer/core/css/css_selector.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition specificity_weight (a b c : Z) : Z := a * 10000 + b * 100 + c.
Theorem specificity_id_dominates : forall a1 b1 c1 a2 b2 c2,
  a2 < a1 -> 0 <= b1 < 100 -> 0 <= c1 < 100 -> 0 <= b2 < 100 -> 0 <= c2 < 100 ->
  specificity_weight a2 b2 c2 < specificity_weight a1 b1 c1.
Proof. intros. unfold specificity_weight. lia. Qed.
