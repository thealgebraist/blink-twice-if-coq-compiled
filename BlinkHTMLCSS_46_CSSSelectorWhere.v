(* Blink2Coq HTML/CSS Synthesis for CSSSelectorWhere *)
(* Source: renderer/core/css/css_selector.cc *)

Require Import ZArith. Open Scope Z_scope.
Definition where_pseudo_specificity : Z := 0.
Theorem where_pseudo_zero_specificity : where_pseudo_specificity = 0.
Proof. reflexivity. Qed.
