Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink AXID Monotonic Allocation Semantics *)
(** Blink Accessibility §1: monotonic unique AXID allocation *)

Definition next_ax_id (cur_id : Z) : Z :=
  cur_id + 1.

Theorem ax_id_strictly_monotonic : forall i,
  i < next_ax_id i.
Proof.
  intros i.
  unfold next_ax_id; lia.
Qed.
