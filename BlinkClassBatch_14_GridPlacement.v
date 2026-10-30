(* Blink2Coq Synthesis for GridPlacement *)
(* Source: third_party/blink/renderer/core/layout/grid/grid_placement.cc *)

Require Import ZArith Bool Lia. Open Scope Z_scope.
Definition reset_cursor_if_dense (cur : Z) (is_dense : bool) : Z :=
  if is_dense then 0 else cur.
Theorem dense_placement_resets_cursor : forall cur,
  reset_cursor_if_dense cur true = 0.
Proof. intros. unfold reset_cursor_if_dense. reflexivity. Qed.
