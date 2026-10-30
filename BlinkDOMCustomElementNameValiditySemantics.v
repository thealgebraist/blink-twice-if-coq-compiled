Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Custom Element Name Validity Semantics *)
(** HTML Standard §4.13.1: valid name requires hyphen and lowercase start *)

Definition is_valid_custom_element_name (has_hyphen starts_with_lower : bool) : bool :=
  andb has_hyphen starts_with_lower.

Theorem valid_name_with_hyphen_and_lower :
  is_valid_custom_element_name true true = true.
Proof.
  unfold is_valid_custom_element_name; reflexivity.
Qed.

Theorem invalid_name_without_hyphen : forall l,
  is_valid_custom_element_name false l = false.
Proof.
  intros l.
  unfold is_valid_custom_element_name; reflexivity.
Qed.
