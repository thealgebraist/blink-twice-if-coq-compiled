(* Blink2Coq Synthesis for TableBorders *)
(* Source: third_party/blink/renderer/core/layout/table/table_borders.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition border_prio (style width : Z) : Z :=
  if style =? 3 then 100000 else width * 10 + style.
Theorem hidden_border_prio_dominates : forall w,
  0 <= w <= 1000 -> border_prio 3 0 > border_prio 1 w.
Proof. intros w Hw. unfold border_prio. simpl. lia. Qed.
