Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Animation Timeline Monotonicity Semantics *)
(** Web Animations §4.3: non-decreasing clock advancement *)

Record TimelineClock := {
  current_time : Z
}.

Definition advance_timeline (clock : TimelineClock) (delta : Z) : TimelineClock :=
  {| current_time := current_time clock + Z.max 0 delta |}.

Theorem timeline_advancement_monotonic : forall clock delta,
  current_time clock <= current_time (advance_timeline clock delta).
Proof.
  intros clock delta.
  unfold advance_timeline; simpl.
  lia.
Qed.
