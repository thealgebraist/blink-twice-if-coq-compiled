Require Import ZArith.
Require Import Lia.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink OpenType GSUB Multiple Substitution Semantics *)
(** OpenType GSUB §3: one glyph decomposes to sequence *)

Definition gsub_multiple_substitute (g target : Z) (repl_seq : list Z) : list Z :=
  if g =? target then repl_seq
  else [g].

Theorem multiple_subst_length_ge_one : forall g target repl_seq,
  (length repl_seq >= 1)%nat ->
  (length (gsub_multiple_substitute g target repl_seq) >= 1)%nat.
Proof.
  intros g target repl_seq Hlen.
  unfold gsub_multiple_substitute.
  destruct (g =? target); simpl; lia.
Qed.
