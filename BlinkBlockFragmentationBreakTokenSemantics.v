Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Block Fragmentation Break Token Semantics *)
(** CSS Fragmentation 3 §4 / §5: break token consumed block size *)

Definition remaining_block_size (consumed total : Z) : Z :=
  Z.max 0 (total - consumed).

Theorem remaining_block_size_sound : forall consumed total,
  consumed <= total ->
  remaining_block_size consumed total = total - consumed /\
  remaining_block_size consumed total >= 0.
Proof.
  intros consumed total Hle.
  unfold remaining_block_size.
  split.
  - apply Z.max_r. lia.
  - apply Z.le_ge. apply Z.le_max_l.
Qed.
