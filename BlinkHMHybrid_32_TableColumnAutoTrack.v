(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record TableColumnAutoTrack := mkTableColumnAutoTrack {
  tablecolumnautotrack_avail_w : Z;
  tablecolumnautotrack_num_cols : Z;
  tablecolumnautotrack_col_idx : Z
}.

Definition auto_col_slice_width (avail_w : Z) (num_cols : Z) (col_idx : Z) : Z :=
  if num_cols <=? 0 then 0 else ((avail_w * (col_idx + 1)) / num_cols) - ((avail_w * col_idx) / num_cols).

Theorem two_auto_col_slices_conserve_width :
  forall (avail_w : Z), auto_col_slice_width avail_w 2 0 + auto_col_slice_width avail_w 2 1 = avail_w.
Proof.
  intros avail_w.
  unfold auto_col_slice_width.
  replace (2 <=? 0) with false by reflexivity.
  replace (0 + 1) with 1 by lia.
  replace (1 + 1) with 2 by lia.
  replace (avail_w * 0) with 0 by ring.
  rewrite Z.div_0_l by lia.
  rewrite Z.div_mul by lia.
  lia.
Qed.
