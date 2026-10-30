From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* HTML Standard §7.13 Document Lifecycle State Monotonic Progression *)
Inductive DocumentLifecycleState :=
  | StateUnstyled
  | StateInStyleRecalc
  | StateStyleClean
  | StateInPerformLayout
  | StateLayoutClean
  | StateInCompositing
  | StateInPaint
  | StatePaintClean.

Definition lifecycle_rank (s : DocumentLifecycleState) : Z :=
  match s with
  | StateUnstyled         => 0
  | StateInStyleRecalc    => 1
  | StateStyleClean       => 2
  | StateInPerformLayout  => 3
  | StateLayoutClean      => 4
  | StateInCompositing    => 5
  | StateInPaint          => 6
  | StatePaintClean       => 7
  end.

Definition state_precedes (s1 s2 : DocumentLifecycleState) : Prop :=
  lifecycle_rank s1 <= lifecycle_rank s2.

Theorem layout_clean_precedes_paint_clean :
  state_precedes StateLayoutClean StatePaintClean.
Proof.
  unfold state_precedes; cbn. lia.
Qed.

Theorem unstyled_is_minimal : forall s,
  state_precedes StateUnstyled s.
Proof.
  intros s. unfold state_precedes; cbn.
  destruct s; cbn; lia.
Qed.

Theorem paint_clean_is_maximal : forall s,
  state_precedes s StatePaintClean.
Proof.
  intros s. unfold state_precedes; cbn.
  destruct s; cbn; lia.
Qed.
