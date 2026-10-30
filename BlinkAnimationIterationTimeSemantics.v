Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Current Iteration Time Semantics *)
(** Web Animations §5.3.6: iteration time modulo bounding *)

Definition compute_iteration_time (active_time iteration_duration : Z) : Z :=
  active_time mod iteration_duration.

Theorem iteration_time_bounded : forall active_time iteration_duration,
  0 < iteration_duration ->
  0 <= compute_iteration_time active_time iteration_duration < iteration_duration.
Proof.
  intros active_time iteration_duration Hdur.
  unfold compute_iteration_time.
  apply Z.mod_pos_bound.
  lia.
Qed.
