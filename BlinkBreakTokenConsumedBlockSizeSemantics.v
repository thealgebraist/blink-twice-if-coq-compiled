Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Consumed Block Size Accumulation Semantics *)
(** Blink LayoutNG Fragmentation: sequential accumulation *)

Definition accumulate_consumed_block_size (prior_consumed fragment_block_size : Z) : Z :=
  prior_consumed + Z.max 0 fragment_block_size.

Theorem consumed_block_size_monotonic : forall prior size,
  prior <= accumulate_consumed_block_size prior size.
Proof.
  intros prior size.
  unfold accumulate_consumed_block_size.
  lia.
Qed.
