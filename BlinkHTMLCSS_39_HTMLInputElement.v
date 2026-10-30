(* Blink2Coq HTML/CSS Synthesis for HTMLInputElement *)
(* Source: renderer/core/html/forms/html_input_element.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition is_step_aligned (val min_val step : Z) : bool :=
  ((val - min_val) mod step =? 0).
Theorem step_alignment_sound : forall val min_val step,
  0 < step -> (val - min_val) mod step = 0 -> is_step_aligned val min_val step = true.
Proof. intros val mi st Hst Hmod. unfold is_step_aligned. rewrite Hmod. reflexivity. Qed.
