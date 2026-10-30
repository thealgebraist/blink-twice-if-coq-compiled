Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Flat Tree Traversal Projection Semantics *)
(** DOM Standard §4.2.2: flat tree composition depth identity *)

Definition flat_tree_depth (tree_depth : Z) : Z :=
  tree_depth.

Theorem flat_tree_depth_identity : forall d,
  flat_tree_depth d = d.
Proof.
  intros d; reflexivity.
Qed.
