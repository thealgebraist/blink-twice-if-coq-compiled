Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Remaining Block Size Calculation Semantics *)
(** Blink LayoutNG Fragmentation: remaining space non-negativity *)

Definition compute_remaining_block_size (total_block_size consumed_block_size : Z) : Z :=
  Z.max 0 (total_block_size - consumed_block_size).

Theorem remaining_block_size_nonneg : forall total consumed,
  0 <= compute_remaining_block_size total consumed.
Proof.
  intros total consumed.
  unfold compute_remaining_block_size.
  lia.
Qed.

Theorem fully_consumed_yields_zero_remaining : forall total consumed,
  total <= consumed ->
  compute_remaining_block_size total consumed = 0.
Proof.
  intros total consumed Hle.
  unfold compute_remaining_block_size.
  lia.
Qed.
