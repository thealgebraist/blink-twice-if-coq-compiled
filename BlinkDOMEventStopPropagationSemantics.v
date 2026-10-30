Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink stopPropagation Termination Semantics *)
(** DOM Standard §2.7: stopPropagation halts dispatch loop *)

Definition dispatch_to_parent (is_stopped : bool) (parent_depth : Z) : Z :=
  if is_stopped then 0 else parent_depth.

Theorem stopped_propagation_zeroes_dispatch : forall d,
  dispatch_to_parent true d = 0.
Proof.
  intros d; reflexivity.
Qed.

Theorem unstopped_propagation_continues : forall d,
  dispatch_to_parent false d = d.
Proof.
  intros d; reflexivity.
Qed.
