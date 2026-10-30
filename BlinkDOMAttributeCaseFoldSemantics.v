Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Attribute Name ASCII Case Folding Semantics *)
(** DOM Standard §4.9: ASCII uppercase maps to lowercase *)

Definition ascii_to_lower_char (c : Z) : Z :=
  if andb (65 <=? c) (c <=? 90) then c + 32 else c.

Theorem uppercase_A_folds_to_lowercase_a :
  ascii_to_lower_char 65 = 97.
Proof.
  unfold ascii_to_lower_char; reflexivity.
Qed.

Theorem lowercase_a_is_invariant :
  ascii_to_lower_char 97 = 97.
Proof.
  unfold ascii_to_lower_char; reflexivity.
Qed.
