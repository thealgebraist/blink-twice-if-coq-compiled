From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.5.3 Table Cell Vertical-Align Middle Centering *)
Definition cell_middle_offset (row_h : Z) (cell_h : Z) : Z :=
  (row_h - cell_h) / 2.

Theorem cell_middle_offset_nonneg : forall row_h cell_h,
  row_h >= cell_h ->
  cell_middle_offset row_h cell_h >= 0.
Proof.
  intros row_h cell_h Hge.
  unfold cell_middle_offset.
  assert (0 <= (row_h - cell_h) / 2).
  { apply Z.div_pos; lia. }
  lia.
Qed.

Theorem cell_middle_offset_fits : forall row_h cell_h,
  row_h >= cell_h ->
  cell_middle_offset row_h cell_h + cell_h <= row_h.
Proof.
  intros row_h cell_h Hge.
  unfold cell_middle_offset.
  assert (Hdiv: (row_h - cell_h) / 2 <= row_h - cell_h) by (apply Z.div_le_upper_bound; lia).
  lia.
Qed.
