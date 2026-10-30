(* Blink2Coq Synthesis for TableLayoutAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition effective_table_column_width (min_content computed : Z) : Z :=
  Z.max min_content computed.
Theorem table_col_width_ge_min_content : forall mc comp,
  mc <= effective_table_column_width mc comp.
Proof. intros. unfold effective_table_column_width. apply Z.le_max_l. Qed.
