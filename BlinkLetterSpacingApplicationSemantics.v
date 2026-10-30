Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Letter Spacing Application Semantics *)
(** CSS Text 3 §8.2: letter-spacing on grapheme cluster boundaries *)

Definition apply_letter_spacing (advance letter_spacing : Z) : Z :=
  advance + letter_spacing.

Theorem zero_letter_spacing_preserves_advance : forall adv,
  apply_letter_spacing adv 0 = adv.
Proof.
  intros adv.
  unfold apply_letter_spacing; lia.
Qed.
