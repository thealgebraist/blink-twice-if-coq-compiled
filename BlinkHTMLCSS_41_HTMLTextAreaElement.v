(* Blink2Coq HTML/CSS Synthesis for HTMLTextAreaElement *)
(* Source: renderer/core/html/forms/html_text_area_element.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem textarea_maxlength_bounded : forall len max_len,
  0 <= max_len -> Z.min len max_len <= max_len.
Proof. intros. apply Z.le_min_r. Qed.
