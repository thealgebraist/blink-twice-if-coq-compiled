Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas 2D State Stack Semantics *)
(** HTML Canvas 2D §2: save/restore pushdown automaton preserves stack depth *)

Definition push_canvas_state (depth : Z) : Z :=
  depth + 1.

Definition pop_canvas_state (depth : Z) : Z :=
  Z.max 0 (depth - 1).

Theorem push_pop_identity : forall d,
  0 <= d ->
  pop_canvas_state (push_canvas_state d) = d.
Proof.
  intros d Hd.
  unfold push_canvas_state, pop_canvas_state; lia.
Qed.
