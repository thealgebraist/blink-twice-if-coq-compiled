(* Blink2Coq HTML/CSS Synthesis for Node *)
(* Source: renderer/core/dom/node.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition child_node_depth (parent_depth : Z) : Z := parent_depth + 1.
Theorem child_node_depth_positive : forall parent_depth,
  0 <= parent_depth -> 0 < child_node_depth parent_depth.
Proof. intros. unfold child_node_depth. lia. Qed.
