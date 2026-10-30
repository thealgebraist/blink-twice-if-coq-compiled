Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Periodic Background Sync Min Interval Semantics *)
(** Periodic Background Sync §5.1: minInterval lower bounding *)

Definition MIN_PERIODIC_INTERVAL : Z := 43200000. (* 12 hours *)

Definition effective_min_interval (req : Z) : Z :=
  if req <? MIN_PERIODIC_INTERVAL then MIN_PERIODIC_INTERVAL else req.

Theorem effective_min_interval_bounded : forall req,
  effective_min_interval req >= MIN_PERIODIC_INTERVAL.
Proof.
  intros req.
  unfold effective_min_interval.
  destruct (req <? MIN_PERIODIC_INTERVAL) eqn:E.
  - lia.
  - apply Z.ltb_ge in E. lia.
Qed.
