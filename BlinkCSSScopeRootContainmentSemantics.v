Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink @scope Root Containment Semantics *)
(** CSS Cascading 6 §3: scoped styles match enclosed subtree *)

Definition is_descendant_of_scope_root (node_depth scope_root_depth : Z) : bool :=
  scope_root_depth <=? node_depth.

Theorem scope_root_matches_deeper_nodes : forall n r,
  r <= n ->
  is_descendant_of_scope_root n r = true.
Proof.
  intros n r H.
  unfold is_descendant_of_scope_root.
  apply Z.leb_le; exact H.
Qed.

Theorem scope_root_rejects_ancestor_nodes : forall n r,
  n < r ->
  is_descendant_of_scope_root n r = false.
Proof.
  intros n r H.
  unfold is_descendant_of_scope_root.
  apply Z.leb_gt; exact H.
Qed.
