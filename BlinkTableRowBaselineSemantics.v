(**
  BlinkTableRowBaselineSemantics.v
  Formal specification of Chromium Blink table row multi-cell baseline alignment
  derived from third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc
  according to W3C CSS 2.1 (§17.5.3 Table Row Height and Multi-Cell Baseline Alignment).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record TableCell := {
  cell_height : Z;
  cell_ascent : Z;
  cell_align_baseline : bool
}.

Definition cell_descent (c : TableCell) : Z :=
  c.(cell_height) - c.(cell_ascent).

Fixpoint aggregate_row_metrics
    (cells : list TableCell) (cur_max_a cur_max_d cur_max_h : Z) : Z * Z * Z :=
  match cells with
  | [] => (cur_max_a, cur_max_d, cur_max_h)
  | c :: rest =>
      let new_max_h := Z.max cur_max_h c.(cell_height) in
      if c.(cell_align_baseline) then
        let new_max_a := Z.max cur_max_a c.(cell_ascent) in
        let new_max_d := Z.max cur_max_d (cell_descent c) in
        aggregate_row_metrics rest new_max_a new_max_d new_max_h
      else
        aggregate_row_metrics rest cur_max_a cur_max_d new_max_h
  end.

Definition compute_row_height
    (cells : list TableCell) (spec_height : Z) : Z * Z :=
  let '(max_a, max_d, max_h) := aggregate_row_metrics cells 0 0 0 in
  let baseline_span := max_a + max_d in
  let final_h := Z.max spec_height (Z.max baseline_span max_h) in
  (final_h, max_a).

(** 1. Invariant Theorems *)

Theorem row_height_bounds_specified_height :
  forall (cells : list TableCell) (spec_h : Z),
    spec_h <= fst (compute_row_height cells spec_h).
Proof.
  intros cells spec_h.
  unfold compute_row_height.
  destruct (aggregate_row_metrics cells 0 0 0) as [[ma md] mh].
  simpl.
  apply Z.le_max_l.
Qed.

Theorem row_height_bounds_baseline_span :
  forall (cells : list TableCell) (spec_h : Z),
    let '((ma, md, mh)) := aggregate_row_metrics cells 0 0 0 in
    ma + md <= fst (compute_row_height cells spec_h).
Proof.
  intros cells spec_h.
  unfold compute_row_height.
  destruct (aggregate_row_metrics cells 0 0 0) as [[ma md] mh].
  simpl.
  pose proof (Z.le_max_r spec_h (Z.max (ma + md) mh)).
  pose proof (Z.le_max_l (ma + md) mh).
  lia.
Qed.

Lemma aggregate_metrics_mh_monotonic :
  forall (cells : list TableCell) (ma md mh : Z),
    mh <= snd (aggregate_row_metrics cells ma md mh).
Proof.
  induction cells as [|head rest IH].
  - intros ma md mh. simpl. lia.
  - intros ma md mh.
    cbn [aggregate_row_metrics].
    destruct (cell_align_baseline head).
    + pose proof (IH (Z.max ma (cell_ascent head)) (Z.max md (cell_descent head)) (Z.max mh (cell_height head))).
      pose proof (Z.le_max_l mh (cell_height head)).
      lia.
    + pose proof (IH ma md (Z.max mh (cell_height head))).
      pose proof (Z.le_max_l mh (cell_height head)).
      lia.
Qed.

Lemma aggregate_metrics_bounds_cell_height :
  forall (cells : list TableCell) (c : TableCell) (ma md mh : Z),
    In c cells ->
    c.(cell_height) <= snd (aggregate_row_metrics cells ma md mh).
Proof.
  induction cells as [|head rest IH].
  - intros c ma md mh Hin. inversion Hin.
  - intros c ma md mh Hin.
    cbn [aggregate_row_metrics].
    destruct Hin as [Heq | Hin].
    + subst head.
      destruct (cell_align_baseline c).
      * pose proof (aggregate_metrics_mh_monotonic rest (Z.max ma (cell_ascent c)) (Z.max md (cell_descent c)) (Z.max mh (cell_height c))).
        pose proof (Z.le_max_r mh (cell_height c)).
        lia.
      * pose proof (aggregate_metrics_mh_monotonic rest ma md (Z.max mh (cell_height c))).
        pose proof (Z.le_max_r mh (cell_height c)).
        lia.
    + destruct (cell_align_baseline head).
      * apply IH. exact Hin.
      * apply IH. exact Hin.
Qed.

Theorem row_height_contains_all_cells :
  forall (cells : list TableCell) (c : TableCell) (spec_h : Z),
    In c cells ->
    c.(cell_height) <= fst (compute_row_height cells spec_h).
Proof.
  intros cells c spec_h Hin.
  unfold compute_row_height.
  destruct (aggregate_row_metrics cells 0 0 0) as [[ma md] mh] eqn:Eagg.
  simpl.
  pose proof (aggregate_metrics_bounds_cell_height cells c 0 0 0 Hin) as Hcell.
  rewrite Eagg in Hcell.
  simpl in Hcell.
  pose proof (Z.le_max_r spec_h (Z.max (ma + md) mh)).
  pose proof (Z.le_max_r (ma + md) mh).
  lia.
Qed.
