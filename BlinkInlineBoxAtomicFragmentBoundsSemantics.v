Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Inline Box Atomic Fragment Bounds Semantics *)
(** CSS 2.1 §10.8.1: inline-block baseline fallback *)

Definition atomic_baseline (has_inflow_line : bool) (line_b box_h : Z) : Z :=
  if has_inflow_line then line_b else box_h.

Theorem baseline_fallback_to_margin_edge : forall line_b box_h,
  atomic_baseline false line_b box_h = box_h.
Proof.
  intros line_b box_h.
  unfold atomic_baseline.
  reflexivity.
Qed.
