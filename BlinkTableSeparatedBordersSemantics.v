(* =========================================================================
   BlinkTableSeparatedBordersSemantics.v
   Formalization of Chromium Blink Separated Borders & Spacing Geometry
   Source: third_party/blink/renderer/core/layout/table/table_layout_utils.cc
           third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc
   Specification: W3C CSS 2.1 §17.6.1 The Separated Borders Model (border-spacing)
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Record SeparatedTableGeometry2Col : Type := mkSeparatedTableGeometry2Col {
  stg_table_border_start : Z;
  stg_table_padding_start : Z;
  stg_table_border_end : Z;
  stg_table_padding_end : Z;
  stg_h_spacing : Z;
  stg_col0_width : Z;
  stg_col1_width : Z
}.

Definition compute_col0_offset (g : SeparatedTableGeometry2Col) : Z :=
  g.(stg_table_border_start) + g.(stg_table_padding_start) + g.(stg_h_spacing).

Definition compute_col1_offset (g : SeparatedTableGeometry2Col) : Z :=
  compute_col0_offset g + g.(stg_col0_width) + g.(stg_h_spacing).

Definition compute_colspan2_width (g : SeparatedTableGeometry2Col) : Z :=
  g.(stg_col0_width) + g.(stg_h_spacing) + g.(stg_col1_width).

Definition compute_table_total_inline_width (g : SeparatedTableGeometry2Col) : Z :=
  compute_col1_offset g + g.(stg_col1_width) + g.(stg_h_spacing) +
  g.(stg_table_padding_end) + g.(stg_table_border_end).

Theorem columns_separated_by_exact_spacing :
  forall g,
    compute_col1_offset g - (compute_col0_offset g + g.(stg_col0_width)) = g.(stg_h_spacing).
Proof.
  intros g.
  unfold compute_col1_offset.
  lia.
Qed.

Theorem no_column_overlap_when_spacing_nonneg :
  forall g,
    0 <= g.(stg_h_spacing) ->
    compute_col0_offset g + g.(stg_col0_width) <= compute_col1_offset g.
Proof.
  intros g Hsp.
  pose proof (columns_separated_by_exact_spacing g) as Hdist.
  lia.
Qed.

Theorem table_total_width_components_sum :
  forall g,
    compute_table_total_inline_width g =
    g.(stg_table_border_start) + g.(stg_table_padding_start) +
    g.(stg_col0_width) + g.(stg_col1_width) +
    3 * g.(stg_h_spacing) +
    g.(stg_table_padding_end) + g.(stg_table_border_end).
Proof.
  intros g.
  unfold compute_table_total_inline_width, compute_col1_offset, compute_col0_offset.
  lia.
Qed.

Theorem compute_col_offsets_deterministic :
  forall g o0 o1,
    o0 = compute_col0_offset g ->
    o1 = compute_col1_offset g ->
    compute_col1_offset g = o0 + g.(stg_col0_width) + g.(stg_h_spacing).
Proof.
  intros g o0 o1 H0 H1.
  subst. reflexivity.
Qed.

