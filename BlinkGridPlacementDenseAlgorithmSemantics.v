Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Grid Placement Dense Algorithm Semantics *)
(** CSS Grid Layout 1 §8.5: dense automatic grid item placement cursor *)

Definition advance_placement_cursor (is_dense : bool) (cur_row cur_col : Z) : Z * Z :=
  if is_dense then (1, 1) else (cur_row, cur_col).

Theorem dense_resets_cursor : forall r c,
  advance_placement_cursor true r c = (1, 1).
Proof.
  intros r c.
  unfold advance_placement_cursor.
  reflexivity.
Qed.

Theorem sparse_preserves_cursor : forall r c,
  advance_placement_cursor false r c = (r, c).
Proof.
  intros r c.
  unfold advance_placement_cursor.
  reflexivity.
Qed.
