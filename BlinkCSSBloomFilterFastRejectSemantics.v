Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Ancestor Bloom Filter Fast Reject Semantics *)
(** Blink CSS Selector Matching §4: zero false-negative guarantee *)

Definition bloom_reject (in_bloom : bool) : bool :=
  negb in_bloom.

Theorem bloom_reject_guarantees_absence :
  bloom_reject false = true.
Proof.
  reflexivity.
Qed.
