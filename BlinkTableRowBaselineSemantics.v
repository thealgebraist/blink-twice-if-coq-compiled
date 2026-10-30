From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS 2.1 §17.5.3 Table Row Baseline Alignment *)
Definition compute_cell_y_offset (row_baseline : Z) (cell_baseline : Z) : Z :=
  row_baseline - cell_baseline.

Theorem cell_y_offset_nonneg : forall row_baseline cell_baseline,
  row_baseline >= cell_baseline ->
  compute_cell_y_offset row_baseline cell_baseline >= 0.
Proof.
  intros row_b cell_b Hge.
  unfold compute_cell_y_offset. lia.
Qed.

Theorem cell_aligned_baseline_exact : forall row_baseline cell_baseline,
  cell_baseline + compute_cell_y_offset row_baseline cell_baseline = row_baseline.
Proof.
  intros row_b cell_b.
  unfold compute_cell_y_offset. lia.
Qed.
