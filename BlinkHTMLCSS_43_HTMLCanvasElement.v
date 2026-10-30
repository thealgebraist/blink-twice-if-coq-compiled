(* Blink2Coq HTML/CSS Synthesis for HTMLCanvasElement *)
(* Source: renderer/core/html/canvas/html_canvas_element.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition effective_canvas_dimension (dim : Z) : Z := Z.max 0 dim.
Theorem canvas_dimension_nonneg : forall dim,
  0 <= effective_canvas_dimension dim.
Proof. intros. unfold effective_canvas_dimension. apply Z.le_max_l. Qed.
