(* Blink2Coq HTML/CSS Synthesis for HTMLImageElement *)
(* Source: renderer/core/html/html_image_element.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition effective_image_density (d : Z) : Z := Z.max 1 d.
Theorem image_density_lower_bound : forall d,
  1 <= effective_image_density d.
Proof. intros. unfold effective_image_density. apply Z.le_max_l. Qed.
