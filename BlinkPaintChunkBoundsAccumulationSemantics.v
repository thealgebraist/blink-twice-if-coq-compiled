Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Paint Chunk Bounds Accumulation Semantics *)
(** CSS Paint 1 §4: visual rect bounding box union *)

Definition accumulate_chunk_span (s1 e1 s2 e2 : Z) : (Z * Z) :=
  (Z.min s1 s2, Z.max e1 e2).

Theorem chunk_bounds_encloses_first : forall s1 e1 s2 e2,
  fst (accumulate_chunk_span s1 e1 s2 e2) <= s1 /\
  e1 <= snd (accumulate_chunk_span s1 e1 s2 e2).
Proof.
  intros s1 e1 s2 e2.
  unfold accumulate_chunk_span; simpl; lia.
Qed.

Theorem chunk_bounds_encloses_second : forall s1 e1 s2 e2,
  fst (accumulate_chunk_span s1 e1 s2 e2) <= s2 /\
  e2 <= snd (accumulate_chunk_span s1 e1 s2 e2).
Proof.
  intros s1 e1 s2 e2.
  unfold accumulate_chunk_span; simpl; lia.
Qed.
