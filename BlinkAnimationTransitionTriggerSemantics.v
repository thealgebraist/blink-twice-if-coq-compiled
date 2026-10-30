Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Transition Triggering Semantics *)
(** CSS Transitions 1 §3: transition trigger condition *)

Definition should_trigger_transition (old_val new_val : Z) : bool :=
  negb (old_val =? new_val).

Theorem transition_triggers_iff_unequal : forall v1 v2,
  should_trigger_transition v1 v2 = true <-> v1 <> v2.
Proof.
  intros v1 v2.
  unfold should_trigger_transition.
  destruct (v1 =? v2) eqn:Heq.
  - simpl.
    apply Z.eqb_eq in Heq.
    split; [discriminate | intros; contradiction].
  - simpl.
    apply Z.eqb_neq in Heq.
    split; auto.
Qed.
