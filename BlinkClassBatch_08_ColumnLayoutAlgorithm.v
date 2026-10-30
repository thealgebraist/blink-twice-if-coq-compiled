(* Blink2Coq Synthesis for ColumnLayoutAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/fragmentation/column_layout_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition resolve_column_count (tot col_w : Z) : Z :=
  Z.max 1 (tot / col_w).
Theorem resolved_column_count_positive : forall tot col_w,
  1 <= resolve_column_count tot col_w.
Proof. intros. unfold resolve_column_count. apply Z.le_max_l. Qed.
