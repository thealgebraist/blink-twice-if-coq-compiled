(* BlinkInfoboxMetadataColumnSemantics.v *)
(* Formal semantics of Blink 2-column Infobox metadata layout algorithm *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/table/ng_table_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record BlinkTableGrid := mkTableGrid {
  grid_left : Z;
  grid_width : Z;
  col1_pct : Z;
  cell_padding_left : Z
}.

Definition compute_col1_width (g : BlinkTableGrid) : Z :=
  (grid_width g * col1_pct g) / 100.

Definition compute_col1_text_x (g : BlinkTableGrid) : Z :=
  grid_left g + cell_padding_left g.

Definition compute_col2_text_x (g : BlinkTableGrid) : Z :=
  grid_left g + compute_col1_width g + cell_padding_left g.

Definition compute_row_baseline (base_y start_offset row_index stride : Z) : Z :=
  base_y + start_offset + row_index * stride.

Theorem col2_strictly_after_col1 :
  forall (g : BlinkTableGrid),
    0 < compute_col1_width g ->
    compute_col1_text_x g < compute_col2_text_x g.
Proof.
  intros g Hw.
  unfold compute_col1_text_x, compute_col2_text_x.
  lia.
Qed.

Theorem row_baselines_strictly_increasing :
  forall (base_y start stride i : Z),
    0 < stride ->
    compute_row_baseline base_y start i stride < compute_row_baseline base_y start (i + 1) stride.
Proof.
  intros base_y start stride i Hstr.
  unfold compute_row_baseline.
  lia.
Qed.

(* Exact Wikipedia Page 2 Infobox parameters *)
Definition p2_infobox_grid : BlinkTableGrid := mkTableGrid 512 256 38 4.

Theorem p2_infobox_exact_coordinates :
  compute_col1_width p2_infobox_grid = 97 /\
  compute_col1_text_x p2_infobox_grid = 516 /\
  compute_col2_text_x p2_infobox_grid = 613 /\
  compute_row_baseline 0 298 0 16 = 298 /\
  compute_row_baseline 0 298 1 16 = 314 /\
  compute_row_baseline 0 298 2 16 = 330 /\
  compute_row_baseline 0 298 3 16 = 346 /\
  compute_row_baseline 0 298 4 16 = 362.
Proof.
  unfold p2_infobox_grid, compute_col1_width, compute_col1_text_x, compute_col2_text_x, compute_row_baseline.
  simpl.
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity |].
  split; [reflexivity | reflexivity].
Qed.
