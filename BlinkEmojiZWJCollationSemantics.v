Require Import ZArith.
Require Import Lia.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Emoji ZWJ Sequence Collation Semantics *)
(** Unicode UTS #51 §2: ZWJ sequence collation *)

Definition is_zwj (cp : Z) : bool :=
  cp =? 8205.

Definition collate_zwj_sequence_pair (cp1 zwj cp2 compound_glyph : Z) : list Z :=
  if is_zwj zwj then [compound_glyph]
  else [cp1; zwj; cp2].

Theorem zwj_collapses_to_single_glyph : forall cp1 cp2 compound,
  length (collate_zwj_sequence_pair cp1 8205 cp2 compound) = 1%nat.
Proof.
  intros cp1 cp2 compound.
  unfold collate_zwj_sequence_pair, is_zwj; simpl.
  reflexivity.
Qed.
