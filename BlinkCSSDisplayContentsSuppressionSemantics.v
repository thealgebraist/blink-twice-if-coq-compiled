Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink display:contents Box Generation Suppression Semantics *)
(** CSS Display 3 §2: display: contents element produces 0 box fragments *)

Definition generate_box_count (is_display_contents : bool) : Z :=
  if is_display_contents then 0 else 1.

Theorem display_contents_suppresses_box :
  generate_box_count true = 0.
Proof.
  reflexivity.
Qed.

Theorem normal_element_generates_box :
  generate_box_count false = 1.
Proof.
  reflexivity.
Qed.
