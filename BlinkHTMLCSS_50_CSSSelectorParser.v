(* Blink2Coq HTML/CSS Synthesis for CSSSelectorParser *)
(* Source: renderer/core/css/parser/css_selector_parser.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem uppercase_lowered_in_range : forall c,
  65 <= c <= 90 -> 97 <= c + 32 <= 122.
Proof. intros. lia. Qed.
