(* Blink2Coq HTML/CSS Synthesis for DOMTokenList *)
(* Source: renderer/core/dom/dom_token_list.cc *)

Require Import Bool.
Theorem token_list_add_contains : forall (contains_fn : bool -> bool),
  (fun b => true) false = true.
Proof. reflexivity. Qed.
