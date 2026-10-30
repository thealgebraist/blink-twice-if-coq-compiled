From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* Blink LayoutNG Physical Fragment Tree Depth-First Traversal *)
Inductive FragmentTree :=
  | FragmentLeaf (id : Z)
  | FragmentBranch (id : Z) (left : FragmentTree) (right : FragmentTree).

Fixpoint count_tree (t : FragmentTree) : nat :=
  match t with
  | FragmentLeaf _ => 1%nat
  | FragmentBranch _ l r => S (count_tree l + count_tree r)
  end.

Theorem tree_count_positive : forall t,
  (count_tree t >= 1)%nat.
Proof.
  intros t. destruct t; cbn; lia.
Qed.
