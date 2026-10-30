(* Blink2Coq HTML/CSS Synthesis for DOMSelection *)
(* Source: renderer/core/editing/dom_selection.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition selection_length (start_off end_off : Z) : Z :=
  Z.max 0 (end_off - start_off).
Theorem collapsed_selection_length_zero : forall off,
  selection_length off off = 0.
Proof. intros. unfold selection_length. rewrite Z.sub_diag. reflexivity. Qed.
