Require Import ZArith.
Require Import Lia.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink OpenType GSUB Ligature Substitution Semantics *)
(** OpenType GSUB §4: ligature prefix collapse *)

Definition gsub_ligature_substitute_pair (g1 g2 target1 target2 ligature_glyph : Z) : list Z :=
  if andb (g1 =? target1) (g2 =? target2) then [ligature_glyph]
  else [g1; g2].

Theorem ligature_collapse_reduces_length : forall g1 g2 target1 target2 lig,
  g1 = target1 ->
  g2 = target2 ->
  length (gsub_ligature_substitute_pair g1 g2 target1 target2 lig) = 1%nat.
Proof.
  intros g1 g2 target1 target2 lig -> ->.
  unfold gsub_ligature_substitute_pair.
  assert (target1 =? target1 = true) by (apply Z.eqb_eq; reflexivity).
  assert (target2 =? target2 = true) by (apply Z.eqb_eq; reflexivity).
  rewrite H, H0; simpl.
  reflexivity.
Qed.
