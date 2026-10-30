(* Blink2Coq Synthesis for BlockLayoutAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/block_layout_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition advance_block_cursor (cur_y child_h : Z) : Z := cur_y + child_h.
Theorem block_cursor_monotonic : forall cur_y child_h,
  0 <= child_h -> cur_y <= advance_block_cursor cur_y child_h.
Proof. intros. unfold advance_block_cursor. lia. Qed.
