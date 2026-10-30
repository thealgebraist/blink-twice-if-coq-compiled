Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Table Rowspan Height Distribution Semantics *)
(** CSS 2.1 §17.5.3: rowspan height distribution *)

Definition distribute_rowspan_excess (rowspan cell_h total_row_h : Z) : Z :=
  Z.max 0 (cell_h - total_row_h) / rowspan.

Theorem distribute_excess_nonneg : forall rowspan cell_h total_row_h,
  rowspan > 0 ->
  distribute_rowspan_excess rowspan cell_h total_row_h >= 0.
Proof.
  intros rowspan cell_h total_row_h Hspan.
  unfold distribute_rowspan_excess.
  assert (0 <= Z.max 0 (cell_h - total_row_h)).
  { apply Z.le_max_l. }
  assert (Hpos : 0 < rowspan) by lia.
  pose proof (Z.div_pos (Z.max 0 (cell_h - total_row_h)) rowspan H Hpos).
  lia.
Qed.
