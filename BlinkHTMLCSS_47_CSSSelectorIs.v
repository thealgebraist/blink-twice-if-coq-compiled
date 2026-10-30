(* Blink2Coq HTML/CSS Synthesis for CSSSelectorIs *)
(* Source: renderer/core/css/css_selector.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition is_pseudo_specificity (s1 s2 : Z) : Z := Z.max s1 s2.
Theorem is_pseudo_maximization : forall s1 s2,
  s1 <= is_pseudo_specificity s1 s2.
Proof. intros. unfold is_pseudo_specificity. apply Z.le_max_l. Qed.
