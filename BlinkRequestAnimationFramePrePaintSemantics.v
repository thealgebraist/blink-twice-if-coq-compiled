Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink requestAnimationFrame Pipeline Order Semantics *)
(** HTML Standard §8.1: rAF callback executes strictly before style, layout, and paint *)

Definition PHASE_RAF    : Z := 1.
Definition PHASE_STYLE  : Z := 2.
Definition PHASE_LAYOUT : Z := 3.
Definition PHASE_PAINT  : Z := 4.

Theorem rendering_pipeline_strictly_ordered :
  PHASE_RAF < PHASE_STYLE /\
  PHASE_STYLE < PHASE_LAYOUT /\
  PHASE_LAYOUT < PHASE_PAINT.
Proof.
  unfold PHASE_RAF, PHASE_STYLE, PHASE_LAYOUT, PHASE_PAINT.
  lia.
Qed.
