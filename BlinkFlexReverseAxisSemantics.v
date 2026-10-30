(* ========================================================================= *)
(*               BlinkFlexReverseAxisSemantics.v                            *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Flex Reverse Main Axis Placement   *)
(* against CSS Flexible Box Layout 1 §5.1. Fully constructive, 0 admits.     *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition reverse_offset (line_size item_offset item_size : Z) : Z :=
  line_size - (item_offset + item_size).

Theorem reverse_offset_in_bounds : forall line_size item_offset item_size,
  0 <= item_offset ->
  item_offset + item_size <= line_size ->
  item_size >= 0 ->
  0 <= reverse_offset line_size item_offset item_size /\
  reverse_offset line_size item_offset item_size + item_size <= line_size.
Proof.
  intros line_size item_offset item_size H1 H2 H3.
  unfold reverse_offset. lia.
Qed.

Theorem reverse_offset_involution : forall line_size item_offset item_size,
  reverse_offset line_size (reverse_offset line_size item_offset item_size) item_size = item_offset.
Proof.
  intros. unfold reverse_offset. lia.
Qed.

Theorem reverse_adjacent_disjoint : forall line_size x1 w1 w2,
  w1 >= 0 -> w2 >= 0 ->
  x1 + w1 + w2 <= line_size ->
  reverse_offset line_size (x1 + w1) w2 + w2 <= reverse_offset line_size x1 w1.
Proof.
  intros. unfold reverse_offset. lia.
Qed.
