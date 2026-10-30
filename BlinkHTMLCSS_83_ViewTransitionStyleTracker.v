(* Blink2Coq HTML/CSS Synthesis for ViewTransitionStyleTracker *)
(* Source: renderer/core/view_transition/view_transition_style_tracker.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition delta_displacement (x_new x_old : Z) : Z := x_new - x_old.
Theorem view_transition_stationary_delta_zero : forall x,
  delta_displacement x x = 0.
Proof. intros. unfold delta_displacement. lia. Qed.
