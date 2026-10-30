Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Word Spacing Application Semantics *)
(** CSS Text 3 §8.1: word-spacing on space characters *)

Definition is_space_character (codepoint : Z) : bool :=
  (codepoint =? 32) || (codepoint =? 160).

Definition apply_word_spacing (codepoint advance word_spacing : Z) : Z :=
  if is_space_character codepoint then advance + word_spacing
  else advance.

Theorem space_receives_word_spacing : forall adv ws,
  apply_word_spacing 32 adv ws = adv + ws.
Proof.
  intros adv ws.
  unfold apply_word_spacing, is_space_character; simpl.
  reflexivity.
Qed.

Theorem non_space_unaffected_by_word_spacing : forall cp adv ws,
  cp <> 32 ->
  cp <> 160 ->
  apply_word_spacing cp adv ws = adv.
Proof.
  intros cp adv ws H1 H2.
  unfold apply_word_spacing, is_space_character.
  assert (cp =? 32 = false) by (apply Z.eqb_neq; auto).
  assert (cp =? 160 = false) by (apply Z.eqb_neq; auto).
  rewrite H, H0; simpl.
  reflexivity.
Qed.
