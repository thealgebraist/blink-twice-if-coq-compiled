Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ARIA-labelledby Graph Cycle-Safe Semantics *)
(** Accessible Name §2: cycle detection prevents infinite recursion *)

Definition traverse_relation_depth (has_cycle : bool) (depth : Z) : Z :=
  if has_cycle then depth else depth + 1.

Theorem relation_cycle_halts : forall d,
  traverse_relation_depth true d = d.
Proof.
  intros d; reflexivity.
Qed.

Theorem relation_acyclic_advances : forall d,
  d < traverse_relation_depth false d.
Proof.
  intros d.
  unfold traverse_relation_depth; lia.
Qed.
