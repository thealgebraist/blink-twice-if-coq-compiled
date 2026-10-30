Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Class Invalidation Set Union Semantics *)
(** Blink Style Invalidation §2: bitset union covers affected elements *)

Definition invalidation_covered (s1 s2 : bool) : bool :=
  orb s1 s2.

Theorem invalidation_union_covers_first : forall s2,
  invalidation_covered true s2 = true.
Proof.
  intros s2; reflexivity.
Qed.

Theorem invalidation_union_covers_second : forall s1,
  invalidation_covered s1 true = true.
Proof.
  intros s1.
  unfold invalidation_covered; destruct s1; reflexivity.
Qed.
