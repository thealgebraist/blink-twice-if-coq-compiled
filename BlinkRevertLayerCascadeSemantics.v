From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Cascading 5 §4 revert-layer Cascade Rollback *)
Definition resolve_revert_layer (prev_layer_val : Z) : Z :=
  prev_layer_val.

Theorem revert_layer_rolls_back_exactly : forall prev_val,
  resolve_revert_layer prev_val = prev_val.
Proof.
  reflexivity.
Qed.
