Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink IndexedDB IDBCursor Direction Monotonicity Semantics *)
(** IndexedDB 3 §5: cursor movement strictly monotonic in key order *)

Definition cursor_advance_next (key step : Z) : Z :=
  key + (if 0 <? step then step else 1).

Definition cursor_advance_prev (key step : Z) : Z :=
  key - (if 0 <? step then step else 1).

Theorem cursor_advance_next_strictly_monotonic : forall k s,
  k < cursor_advance_next k s.
Proof.
  intros k s.
  unfold cursor_advance_next.
  destruct (0 <? s) eqn:Hs; [apply Z.ltb_lt in Hs | ]; lia.
Qed.

Theorem cursor_advance_prev_strictly_monotonic : forall k s,
  cursor_advance_prev k s < k.
Proof.
  intros k s.
  unfold cursor_advance_prev.
  destruct (0 <? s) eqn:Hs; [apply Z.ltb_lt in Hs | ]; lia.
Qed.
