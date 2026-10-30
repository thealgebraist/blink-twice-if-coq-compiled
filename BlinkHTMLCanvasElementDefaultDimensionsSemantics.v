Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink HTMLCanvasElement Default Dimensions Semantics *)
(** HTML Standard §4.12.5: default canvas dimensions (300, 150) *)

Definition default_canvas_dimensions : (Z * Z) :=
  (300, 150).

Theorem default_canvas_dimensions_positive :
  0 < fst default_canvas_dimensions /\
  0 < snd default_canvas_dimensions.
Proof.
  unfold default_canvas_dimensions; simpl; lia.
Qed.
