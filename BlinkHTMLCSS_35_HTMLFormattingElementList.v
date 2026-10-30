(* Blink2Coq HTML/CSS Synthesis for HTMLFormattingElementList *)
(* Source: renderer/core/html/parser/html_formatting_element_list.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem formatting_marker_boundary_bounded : forall sz marker_pos,
  0 <= marker_pos <= sz -> marker_pos <= sz.
Proof. intros. lia. Qed.
