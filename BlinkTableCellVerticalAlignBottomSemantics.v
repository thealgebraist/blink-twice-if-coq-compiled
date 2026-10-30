From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.5.3 Table Cell Vertical-Align Bottom *)
Definition cell_bottom_offset (row_h : Z) (cell_h : Z) : Z :=
  row_h - cell_h.

Theorem cell_bottom_offset_exact : forall row_h cell_h,
  cell_bottom_offset row_h cell_h + cell_h = row_h.
Proof.
  intros row_h cell_h.
  unfold cell_bottom_offset. lia.
Qed.

Theorem cell_bottom_offset_nonneg : forall row_h cell_h,
  row_h >= cell_h ->
  cell_bottom_offset row_h cell_h >= 0.
Proof.
  intros row_h cell_h Hge.
  unfold cell_bottom_offset. lia.
Qed.
