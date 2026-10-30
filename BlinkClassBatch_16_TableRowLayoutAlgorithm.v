(* Blink2Coq Synthesis for TableRowLayoutAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition distribute_rowspan_excess (excess num_rows : Z) : Z :=
  if num_rows <=? 0 then 0 else excess / num_rows.
Theorem distribute_rowspan_excess_nonneg : forall excess num_rows,
  0 <= excess -> 0 < num_rows -> 0 <= distribute_rowspan_excess excess num_rows.
Proof.
  intros ex n Hex Hn. unfold distribute_rowspan_excess.
  destruct (n <=? 0) eqn:En; [apply Z.leb_le in En; lia |].
  apply Z.div_pos; lia.
Qed.
