From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §4 Empty Row Height Collapsing *)
Record TableRowInfo := {
  tri_cell_count : Z;
  tri_min_height : Z;
  tri_content_height : Z
}.

Definition compute_row_height (r : TableRowInfo) : Z :=
  if andb (tri_cell_count r =? 0) (tri_min_height r =? 0) then 0
  else Z.max (tri_min_height r) (tri_content_height r).

Theorem empty_row_collapses_to_zero : forall r,
  tri_cell_count r = 0 ->
  tri_min_height r = 0 ->
  compute_row_height r = 0.
Proof.
  intros [c min_h cnt_h] Hc Hmin.
  cbn in *. subst.
  unfold compute_row_height; cbn.
  reflexivity.
Qed.

Theorem occupied_row_ge_min : forall r,
  tri_cell_count r > 0 ->
  compute_row_height r >= tri_min_height r.
Proof.
  intros [c min_h cnt_h] Hc.
  cbn in *.
  unfold compute_row_height; cbn.
  destruct (c =? 0) eqn:Ec.
  - apply Z.eqb_eq in Ec. lia.
  - cbn. lia.
Qed.
