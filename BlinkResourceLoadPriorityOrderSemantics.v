Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Resource Load Priority Total Order Semantics *)
(** Blink Resource Loading §2: VeryLow < Low < Medium < High < VeryHigh *)

Definition PRIORITY_VERY_LOW   : Z := 0.
Definition PRIORITY_LOW        : Z := 1.
Definition PRIORITY_MEDIUM     : Z := 2.
Definition PRIORITY_HIGH       : Z := 3.
Definition PRIORITY_VERY_HIGH  : Z := 4.

Theorem priority_strictly_ordered :
  PRIORITY_VERY_LOW < PRIORITY_LOW /\
  PRIORITY_LOW < PRIORITY_MEDIUM /\
  PRIORITY_MEDIUM < PRIORITY_HIGH /\
  PRIORITY_HIGH < PRIORITY_VERY_HIGH.
Proof.
  unfold PRIORITY_VERY_LOW, PRIORITY_LOW, PRIORITY_MEDIUM, PRIORITY_HIGH, PRIORITY_VERY_HIGH.
  lia.
Qed.
