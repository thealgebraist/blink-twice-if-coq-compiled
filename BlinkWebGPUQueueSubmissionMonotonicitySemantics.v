Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Queue Submission Monotonicity Semantics *)
(** WebGPU §13.1: queue submission serial monotonicity *)

Definition advance_submission_id (curr_id : Z) : Z :=
  curr_id + 1.

Theorem submission_id_strictly_monotonic : forall id,
  id < advance_submission_id id.
Proof.
  intros id.
  unfold advance_submission_id.
  lia.
Qed.
