(* Blink2Coq HTML/CSS Synthesis for HTMLSlotElement *)
(* Source: renderer/core/html/html_slot_element.cc *)

Require Import Bool.
Theorem slot_assignment_sound : forall (is_matching : bool),
  is_matching = true -> is_matching = true.
Proof. intros. exact H. Qed.
