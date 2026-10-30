(* Blink2Coq HTML/CSS Synthesis for HTMLDialogElement *)
(* Source: renderer/core/html/html_dialog_element.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition next_top_layer_index (curr_top : Z) : Z := curr_top + 1.
Theorem top_layer_strictly_greater : forall top,
  top < next_top_layer_index top.
Proof. intros. unfold next_top_layer_index. lia. Qed.
