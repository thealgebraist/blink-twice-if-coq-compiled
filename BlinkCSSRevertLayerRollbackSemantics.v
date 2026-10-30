Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink revert-layer Keyword Rollback Semantics *)
(** CSS Cascading 5 §7: revert-layer rolls back to previous cascade layer *)

Definition revert_layer_step (current_layer : Z) : Z :=
  Z.max 0 (current_layer - 1).

Theorem revert_layer_nonneg : forall l,
  0 <= revert_layer_step l.
Proof.
  intros l.
  unfold revert_layer_step; lia.
Qed.

Theorem revert_layer_strictly_decreases : forall l,
  0 < l ->
  revert_layer_step l < l.
Proof.
  intros l Hl.
  unfold revert_layer_step; lia.
Qed.
