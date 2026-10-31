(* BlinkCladesTableRowBaselineSemantics.v *)
(* Formal semantics of Blink Table Row baseline alignment in Clades Table *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/table/ng_table_row_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record BlinkTableCellLayout := mkTableCellLayout {
  cell_top : Z;
  cell_height : Z;
  cell_padding_top : Z;
  cell_font_ascent : Z
}.

Definition compute_cell_baseline (c : BlinkTableCellLayout) : Z :=
  cell_top c + cell_padding_top c + cell_font_ascent c.

Theorem cell_baseline_monotonic :
  forall (c : BlinkTableCellLayout),
    0 <= cell_padding_top c ->
    0 <= cell_font_ascent c ->
    cell_top c <= compute_cell_baseline c.
Proof.
  intros c Hpad Hasc.
  unfold compute_cell_baseline.
  lia.
Qed.

Theorem cell_baseline_contained :
  forall (c : BlinkTableCellLayout),
    0 <= cell_padding_top c ->
    0 <= cell_font_ascent c ->
    cell_padding_top c + cell_font_ascent c <= cell_height c ->
    compute_cell_baseline c <= cell_top c + cell_height c.
Proof.
  intros c Hpad Hasc Hfit.
  unfold compute_cell_baseline.
  lia.
Qed.

(* Exact Page 3 Clades Table 5-row baseline progression *)
Definition clades_head_y : Z := 156.
Definition clades_r1_y : Z := 177.
Definition clades_r2_y : Z := 196.
Definition clades_r3_y : Z := 215.
Definition clades_r4_y : Z := 234.

Definition clades_head_cell : BlinkTableCellLayout := mkTableCellLayout clades_head_y 21 7 8.
Definition clades_r1_cell : BlinkTableCellLayout := mkTableCellLayout clades_r1_y 19 6 8.
Definition clades_r2_cell : BlinkTableCellLayout := mkTableCellLayout clades_r2_y 19 6 8.
Definition clades_r3_cell : BlinkTableCellLayout := mkTableCellLayout clades_r3_y 19 6 8.
Definition clades_r4_cell : BlinkTableCellLayout := mkTableCellLayout clades_r4_y 19 6 8.

Theorem clades_table_baselines_exact :
  compute_cell_baseline clades_head_cell = 171 /\
  compute_cell_baseline clades_r1_cell = 191 /\
  compute_cell_baseline clades_r2_cell = 210 /\
  compute_cell_baseline clades_r3_cell = 229 /\
  compute_cell_baseline clades_r4_cell = 248.
Proof.
  unfold compute_cell_baseline.
  simpl.
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity | reflexivity].
Qed.
