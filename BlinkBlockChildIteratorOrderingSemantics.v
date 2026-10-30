Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Block Child Iterator Ordering Semantics *)
(** CSS 2.1 §8.3.1: block formatting context margin collapsing chain *)

Definition advance_cursor_y (cursor_y margin_height box_height : Z) : Z :=
  cursor_y + margin_height + box_height.

Theorem cursor_monotonic : forall c m h,
  m >= 0 ->
  h >= 0 ->
  advance_cursor_y c m h >= c.
Proof.
  intros c m h Hm Hh.
  unfold advance_cursor_y.
  lia.
Qed.
