Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink OpenType GSUB Single Substitution Semantics *)
(** OpenType GSUB §2: Format 1 & 2 single glyph replacement *)

Definition gsub_single_substitute (glyph_id target_glyph replacement_glyph : Z) : Z :=
  if glyph_id =? target_glyph then replacement_glyph
  else glyph_id.

Theorem gsub_substitutes_target : forall target repl,
  gsub_single_substitute target target repl = repl.
Proof.
  intros target repl.
  unfold gsub_single_substitute.
  assert (target =? target = true) by (apply Z.eqb_eq; reflexivity).
  rewrite H; reflexivity.
Qed.

Theorem gsub_preserves_non_target : forall g target repl,
  g <> target ->
  gsub_single_substitute g target repl = g.
Proof.
  intros g target repl Hneq.
  unfold gsub_single_substitute.
  assert (g =? target = false) by (apply Z.eqb_neq; auto).
  rewrite H; reflexivity.
Qed.
