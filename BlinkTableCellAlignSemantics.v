(* =========================================================================
   BlinkTableCellAlignSemantics.v
   Formalization of Chromium Blink Table Cell Layout & Vertical Alignment
   Source: third_party/blink/renderer/core/layout/table/table_cell_layout_algorithm.cc
   Specification: W3C CSS 2.1 §17.5.3 Cell Vertical Alignment (top, middle, bottom, baseline)
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive TableCellVAlign : Type :=
  | VAlignTop
  | VAlignMiddle
  | VAlignBottom
  | VAlignBaseline.

Record TableCellMetrics : Type := mkTableCellMetrics {
  tcm_border_top : Z;
  tcm_border_bottom : Z;
  tcm_padding_top : Z;
  tcm_padding_bottom : Z;
  tcm_content_height : Z;
  tcm_row_height : Z;
  tcm_cell_baseline : Z;
  tcm_row_baseline : Z
}.

Definition compute_cell_vertical_offset
    (align : TableCellVAlign) (m : TableCellMetrics) : Z :=
  let bp_top := m.(tcm_border_top) + m.(tcm_padding_top) in
  let bp_bot := m.(tcm_border_bottom) + m.(tcm_padding_bottom) in
  let total_insets := bp_top + bp_bot in
  let delta := Z.max 0 (m.(tcm_row_height) - (total_insets + m.(tcm_content_height))) in
  match align with
  | VAlignTop => bp_top
  | VAlignMiddle => bp_top + (delta / 2)
  | VAlignBottom => bp_top + delta
  | VAlignBaseline =>
      let base_shift := Z.max 0 (m.(tcm_row_baseline) - m.(tcm_cell_baseline)) in
      bp_top + base_shift
  end.

Theorem cell_offset_nonneg :
  forall align m,
    0 <= m.(tcm_border_top) ->
    0 <= m.(tcm_padding_top) ->
    0 <= compute_cell_vertical_offset align m.
Proof.
  intros align m Hbt Hpt.
  unfold compute_cell_vertical_offset.
  set (bp_top := m.(tcm_border_top) + m.(tcm_padding_top)).
  set (bp_bot := m.(tcm_border_bottom) + m.(tcm_padding_bottom)).
  set (delta := Z.max 0 (m.(tcm_row_height) - (bp_top + bp_bot + m.(tcm_content_height)))).
  assert (Hbp_pos : 0 <= bp_top) by lia.
  assert (Hdelta_pos : 0 <= delta) by (apply Z.le_max_l).
  destruct align.
  - exact Hbp_pos.
  - assert (0 <= delta / 2) by (apply Z.div_pos; lia). lia.
  - lia.
  - pose proof (Z.le_max_l 0 (tcm_row_baseline m - tcm_cell_baseline m)). lia.
Qed.

Theorem cell_content_contained_top :
  forall m,
    0 <= m.(tcm_border_bottom) + m.(tcm_padding_bottom) ->
    m.(tcm_border_top) + m.(tcm_padding_top) +
    m.(tcm_border_bottom) + m.(tcm_padding_bottom) + m.(tcm_content_height) <= m.(tcm_row_height) ->
    compute_cell_vertical_offset VAlignTop m + m.(tcm_content_height) <= m.(tcm_row_height).
Proof.
  intros m Hbp_bot Hfits.
  unfold compute_cell_vertical_offset.
  lia.
Qed.

Theorem cell_content_contained_bottom :
  forall m,
    0 <= m.(tcm_border_bottom) + m.(tcm_padding_bottom) ->
    m.(tcm_border_top) + m.(tcm_padding_top) +
    m.(tcm_border_bottom) + m.(tcm_padding_bottom) + m.(tcm_content_height) <= m.(tcm_row_height) ->
    compute_cell_vertical_offset VAlignBottom m + m.(tcm_content_height) <= m.(tcm_row_height).
Proof.
  intros m Hbp_bot Hfits.
  unfold compute_cell_vertical_offset.
  set (bp_top := m.(tcm_border_top) + m.(tcm_padding_top)).
  set (bp_bot := m.(tcm_border_bottom) + m.(tcm_padding_bottom)).
  assert (Hdelta : Z.max 0 (m.(tcm_row_height) - (bp_top + bp_bot + m.(tcm_content_height))) =
                   m.(tcm_row_height) - (bp_top + bp_bot + m.(tcm_content_height))).
  { apply Z.max_r. lia. }
  rewrite Hdelta.
  lia.
Qed.

Theorem cell_content_contained_middle :
  forall m,
    0 <= m.(tcm_border_bottom) + m.(tcm_padding_bottom) ->
    m.(tcm_border_top) + m.(tcm_padding_top) +
    m.(tcm_border_bottom) + m.(tcm_padding_bottom) + m.(tcm_content_height) <= m.(tcm_row_height) ->
    compute_cell_vertical_offset VAlignMiddle m + m.(tcm_content_height) <= m.(tcm_row_height).
Proof.
  intros m Hbp_bot Hfits.
  unfold compute_cell_vertical_offset.
  set (bp_top := m.(tcm_border_top) + m.(tcm_padding_top)).
  set (bp_bot := m.(tcm_border_bottom) + m.(tcm_padding_bottom)).
  set (raw_delta := m.(tcm_row_height) - (bp_top + bp_bot + m.(tcm_content_height))).
  assert (Hdelta : Z.max 0 raw_delta = raw_delta) by (apply Z.max_r; lia).
  rewrite Hdelta.
  assert (raw_delta / 2 <= raw_delta).
  { apply Z.div_le_upper_bound; lia. }
  lia.
Qed.

Theorem compute_cell_offset_deterministic :
  forall align m o1 o2,
    o1 = compute_cell_vertical_offset align m ->
    o2 = compute_cell_vertical_offset align m ->
    o1 = o2.
Proof.
  intros align m o1 o2 H1 H2.
  subst. reflexivity.
Qed.

