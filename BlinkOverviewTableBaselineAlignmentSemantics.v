(* BlinkOverviewTableBaselineAlignmentSemantics.v *)
(* Formal semantics of Blink Overview Table row baseline alignment on Page 1 *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/table/ng_table_row_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record OverviewTableRow := mkOverviewTableRow {
  row_top_y : Z;
  row_height : Z;
  is_header : bool
}.

Definition compute_overview_row_baseline (r : OverviewTableRow) : Z :=
  if is_header r then row_top_y r + 15
  else row_top_y r + 14.

Theorem overview_row_baseline_contained :
  forall (r : OverviewTableRow),
    0 < row_height r ->
    16 <= row_height r ->
    row_top_y r < compute_overview_row_baseline r /\
    compute_overview_row_baseline r <= row_top_y r + row_height r.
Proof.
  intros r Hpos Hmin.
  unfold compute_overview_row_baseline.
  destruct (is_header r); lia.
Qed.

(* Exact Page 1 Overview Table row coordinates:
   Header: y=376, h=21 -> baseline = 376 + 15 = 391
   Row 1:  y=397, h=19 -> baseline = 397 + 14 = 411
   Row 2:  y=416, h=19 -> baseline = 416 + 14 = 430
   Row 3:  y=435, h=19 -> baseline = 435 + 14 = 449
   Row 4:  y=454, h=19 -> baseline = 454 + 14 = 468 *)
Definition p1_row_head : OverviewTableRow := mkOverviewTableRow 376 21 true.
Definition p1_row_1 : OverviewTableRow := mkOverviewTableRow 397 19 false.
Definition p1_row_2 : OverviewTableRow := mkOverviewTableRow 416 19 false.
Definition p1_row_3 : OverviewTableRow := mkOverviewTableRow 435 19 false.
Definition p1_row_4 : OverviewTableRow := mkOverviewTableRow 454 19 false.

Theorem p1_overview_table_baselines_exact :
  compute_overview_row_baseline p1_row_head = 391 /\
  compute_overview_row_baseline p1_row_1 = 411 /\
  compute_overview_row_baseline p1_row_2 = 430 /\
  compute_overview_row_baseline p1_row_3 = 449 /\
  compute_overview_row_baseline p1_row_4 = 468.
Proof.
  unfold compute_overview_row_baseline, p1_row_head, p1_row_1, p1_row_2, p1_row_3, p1_row_4.
  simpl.
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity | reflexivity].
Qed.

