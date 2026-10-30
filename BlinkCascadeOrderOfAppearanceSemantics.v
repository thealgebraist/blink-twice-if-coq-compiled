From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Cascading 5 §3 Document Order Tie-Breaking *)
Definition resolve_order_of_appearance (idx1 idx2 : Z) : Z :=
  Z.max idx1 idx2.

Theorem later_declaration_wins : forall idx1 idx2,
  idx1 < idx2 ->
  resolve_order_of_appearance idx1 idx2 = idx2.
Proof.
  intros idx1 idx2 Hlt.
  unfold resolve_order_of_appearance.
  lia.
Qed.

Theorem order_resolution_comm : forall idx1 idx2,
  resolve_order_of_appearance idx1 idx2 = resolve_order_of_appearance idx2 idx1.
Proof.
  intros. unfold resolve_order_of_appearance. lia.
Qed.
