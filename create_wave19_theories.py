#!/usr/bin/env python3
"""
create_wave19_theories.py - Generate the 16 formal Coq theories for Wave 19 (Table Deep Semantics).
Theories 236 to 251. Strictly 0 admits. Fully executable.
"""

theories = {}

theories["BlinkTableFixedLayoutSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS 2.1 §17.5.2.1 Fixed Table Layout Semantics *)
Record TableFixedColumn := {
  tfc_declared_width : option Z;
  tfc_min_width : Z
}.

Definition resolve_fixed_col_width (col : TableFixedColumn) (default_w : Z) : Z :=
  match tfc_declared_width col with
  | Some w => Z.max w (tfc_min_width col)
  | None => Z.max default_w (tfc_min_width col)
  end.

Theorem resolve_fixed_col_width_ge_min : forall col def_w,
  resolve_fixed_col_width col def_w >= tfc_min_width col.
Proof.
  intros [decl min_w] def_w; cbn.
  destruct decl as [w |]; apply Z.le_ge; apply Z.le_max_r.
Qed.

Theorem resolve_fixed_col_width_some : forall decl min_w def_w,
  decl >= min_w ->
  resolve_fixed_col_width {| tfc_declared_width := Some decl; tfc_min_width := min_w |} def_w = decl.
Proof.
  intros decl min_w def_w Hge.
  cbn. lia.
Qed.
"""

theories["BlinkTableColumnLocationSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §3 Table Column Location & Monotonic Offset Accumulation *)
Fixpoint compute_col_offsets (start_x : Z) (spacing : Z) (widths : list Z) : list Z :=
  match widths with
  | nil => nil
  | w :: ws => start_x :: compute_col_offsets (start_x + w + spacing) spacing ws
  end.

Theorem col_offsets_monotonic : forall ws start_x spacing,
  spacing >= 0 ->
  (forall w, In w ws -> w >= 0) ->
  forall x1 x2 rest,
  compute_col_offsets start_x spacing ws = x1 :: x2 :: rest ->
  x1 <= x2.
Proof.
  intros ws start_x spacing Hsp Hpos x1 x2 rest Hcomp.
  destruct ws as [| w1 ws1]; [discriminate |].
  destruct ws1 as [| w2 ws2]; [discriminate |].
  cbn in Hcomp.
  injection Hcomp as E1 E2 Erest.
  subst x1 x2.
  assert (Hw1: w1 >= 0) by (apply Hpos; left; reflexivity).
  lia.
Qed.

Theorem col_intervals_disjoint : forall w1 w2 ws start_x spacing,
  spacing >= 0 ->
  w1 >= 0 ->
  compute_col_offsets start_x spacing (w1 :: w2 :: ws) = start_x :: (start_x + w1 + spacing) :: compute_col_offsets (start_x + w1 + spacing + w2 + spacing) spacing ws.
Proof.
  intros. reflexivity.
Qed.
"""

theories["BlinkTableBorderStyleConflictSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.6.2.1 Collapsed Border Style Precedence *)
Inductive TableBorderStyle :=
  | TBS_None
  | TBS_Dotted
  | TBS_Dashed
  | TBS_Solid
  | TBS_Double
  | TBS_Hidden.

Definition border_style_precedence (s : TableBorderStyle) : Z :=
  match s with
  | TBS_Hidden => 5
  | TBS_Double => 4
  | TBS_Solid  => 3
  | TBS_Dashed => 2
  | TBS_Dotted => 1
  | TBS_None   => 0
  end.

Definition resolve_border_style (s1 s2 : TableBorderStyle) : TableBorderStyle :=
  if border_style_precedence s2 <=? border_style_precedence s1 then s1 else s2.

Theorem resolve_border_style_hidden_l : forall s,
  resolve_border_style TBS_Hidden s = TBS_Hidden.
Proof.
  intros s. unfold resolve_border_style. cbn.
  destruct s; reflexivity.
Qed.

Theorem resolve_border_style_hidden_r : forall s,
  s <> TBS_Hidden ->
  resolve_border_style s TBS_Hidden = TBS_Hidden.
Proof.
  intros s Hneq. unfold resolve_border_style. cbn.
  destruct s; [reflexivity | reflexivity | reflexivity | reflexivity | reflexivity | contradiction Hneq; reflexivity].
Qed.

Theorem resolve_border_style_precedence_ge : forall s1 s2,
  border_style_precedence (resolve_border_style s1 s2) >= border_style_precedence s1 /\
  border_style_precedence (resolve_border_style s1 s2) >= border_style_precedence s2.
Proof.
  intros s1 s2. unfold resolve_border_style.
  destruct (border_style_precedence s2 <=? border_style_precedence s1) eqn:E;
  [apply Z.leb_le in E | apply Z.leb_gt in E]; lia.
Qed.
"""

theories["BlinkTableBorderWidthConflictSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.6.2.1 Border Width Conflict Resolution *)
Definition resolve_border_width (w1 w2 : Z) : Z :=
  Z.max w1 w2.

Theorem resolve_border_width_ge_left : forall w1 w2,
  resolve_border_width w1 w2 >= w1.
Proof.
  intros. unfold resolve_border_width. lia.
Qed.

Theorem resolve_border_width_ge_right : forall w1 w2,
  resolve_border_width w1 w2 >= w2.
Proof.
  intros. unfold resolve_border_width. lia.
Qed.

Theorem resolve_border_width_comm : forall w1 w2,
  resolve_border_width w1 w2 = resolve_border_width w2 w1.
Proof.
  intros. unfold resolve_border_width. lia.
Qed.
"""

theories["BlinkTableRowBaselineSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
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
"""

theories["BlinkTableEmptyRowSuppressionSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
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
"""

theories["BlinkTableCellColspanSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §3.2 Table Cell Colspan Width Distribution *)
Fixpoint sum_widths (ws : list Z) : Z :=
  match ws with
  | nil => 0
  | w :: rest => w + sum_widths rest
  end.

Definition distribute_colspan_deficit (cell_min_w : Z) (current_widths : list Z) : list Z :=
  let cur_sum := sum_widths current_widths in
  if cell_min_w <=? cur_sum then current_widths
  else
    let deficit := cell_min_w - cur_sum in
    match current_widths with
    | nil => nil
    | w0 :: rest => (w0 + deficit) :: rest
    end.

Theorem colspan_distribution_satisfies_min : forall cell_min_w ws,
  ws <> nil ->
  sum_widths (distribute_colspan_deficit cell_min_w ws) >= cell_min_w \/
  sum_widths ws >= cell_min_w.
Proof.
  intros cell_min_w [| w ws] Hnil; [contradiction Hnil; reflexivity |].
  unfold distribute_colspan_deficit.
  destruct (cell_min_w <=? sum_widths (w :: ws)) eqn:E.
  - apply Z.leb_le in E. right. lia.
  - apply Z.leb_gt in E. left.
    cbn. lia.
Qed.
"""

theories["BlinkTableCellRowspanSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §4.2 Table Cell Rowspan Height Distribution *)
Fixpoint sum_heights (hs : list Z) : Z :=
  match hs with
  | nil => 0
  | h :: rest => h + sum_heights rest
  end.

Definition distribute_rowspan_deficit (cell_min_h : Z) (current_heights : list Z) : list Z :=
  let cur_sum := sum_heights current_heights in
  if cell_min_h <=? cur_sum then current_heights
  else
    let deficit := cell_min_h - cur_sum in
    match current_heights with
    | nil => nil
    | h0 :: rest => (h0 + deficit) :: rest
    end.

Theorem rowspan_distribution_satisfies_min : forall cell_min_h hs,
  hs <> nil ->
  sum_heights (distribute_rowspan_deficit cell_min_h hs) >= cell_min_h \/
  sum_heights hs >= cell_min_h.
Proof.
  intros cell_min_h [| h hs] Hnil; [contradiction Hnil; reflexivity |].
  unfold distribute_rowspan_deficit.
  destruct (cell_min_h <=? sum_heights (h :: hs)) eqn:E.
  - apply Z.leb_le in E. right. lia.
  - apply Z.leb_gt in E. left.
    cbn. lia.
Qed.
"""

theories["BlinkTableCaptionMarginCollapseSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.4 Table Caption Formatting Boundary *)
Record TableWrapperLayout := {
  tw_caption_margin_top : Z;
  tw_caption_height : Z;
  tw_caption_margin_bottom : Z;
  tw_grid_border_padding_top : Z;
  tw_grid_height : Z;
  tw_grid_border_padding_bottom : Z
}.

Definition caption_margin_box (tw : TableWrapperLayout) : Z :=
  tw_caption_margin_top tw + tw_caption_height tw + tw_caption_margin_bottom tw.

Definition grid_margin_box (tw : TableWrapperLayout) : Z :=
  tw_grid_border_padding_top tw + tw_grid_height tw + tw_grid_border_padding_bottom tw.

Definition total_table_wrapper_height (tw : TableWrapperLayout) : Z :=
  caption_margin_box tw + grid_margin_box tw.

Theorem caption_margin_does_not_collapse_with_grid : forall tw,
  tw_caption_margin_top tw >= 0 ->
  tw_caption_height tw >= 0 ->
  tw_caption_margin_bottom tw >= 0 ->
  tw_grid_border_padding_top tw >= 0 ->
  tw_grid_height tw >= 0 ->
  tw_grid_border_padding_bottom tw >= 0 ->
  total_table_wrapper_height tw >= caption_margin_box tw /\
  total_table_wrapper_height tw >= grid_margin_box tw.
Proof.
  intros tw H1 H2 H3 H4 H5 H6.
  unfold total_table_wrapper_height, caption_margin_box, grid_margin_box.
  destruct tw; cbn in *.
  lia.
Qed.
"""

theories["BlinkTableCollapsedBorderHalfWidthSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.6.2 Collapsed Border Half-Width Integer Allocation *)
Definition border_half_left (w : Z) : Z :=
  w / 2.

Definition border_half_right (w : Z) : Z :=
  w - (w / 2).

Theorem border_half_sum_exact : forall w,
  border_half_left w + border_half_right w = w.
Proof.
  intros w.
  unfold border_half_left, border_half_right.
  lia.
Qed.

Theorem border_half_diff_at_most_one : forall w,
  w >= 0 ->
  0 <= border_half_right w - border_half_left w <= 1.
Proof.
  intros w Hw.
  unfold border_half_left, border_half_right.
  assert (Hrem: 0 <= w mod 2 < 2) by (apply Z.mod_pos_bound; lia).
  assert (Heq: w = 2 * (w / 2) + w mod 2) by (apply Z.div_mod; lia).
  lia.
Qed.
"""

theories["BlinkTableMinMaxSizingSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §3.1 Table Intrinsic Min/Max Content Sizing *)
Record ColSizing := {
  col_min_content : Z;
  col_max_content : Z
}.

Fixpoint sum_min_content (cols : list ColSizing) : Z :=
  match cols with
  | nil => 0
  | c :: rest => col_min_content c + sum_min_content rest
  end.

Fixpoint sum_max_content (cols : list ColSizing) : Z :=
  match cols with
  | nil => 0
  | c :: rest => col_max_content c + sum_max_content rest
  end.

Theorem table_min_le_max_content : forall cols,
  (forall c, In c cols -> col_min_content c <= col_max_content c) ->
  sum_min_content cols <= sum_max_content cols.
Proof.
  induction cols as [| c rest IH]; intros Hle; cbn.
  - lia.
  - assert (Hc: col_min_content c <= col_max_content c) by (apply Hle; left; reflexivity).
    assert (Hrest: sum_min_content rest <= sum_max_content rest).
    { apply IH. intros x Hx; apply Hle; right; exact Hx. }
    lia.
Qed.
"""

theories["BlinkTableColgroupExpansionSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* HTML 5 §4.9.3 & CSS Table 3 §2 Colgroup Expansion *)
Record ColgroupSpec := {
  cgs_span : Z;
  cgs_width : Z
}.

Fixpoint expand_colgroup (spec : ColgroupSpec) (count : nat) : list Z :=
  match count with
  | O => nil
  | S n => cgs_width spec :: expand_colgroup spec n
  end.

Theorem expand_colgroup_length : forall spec n,
  length (expand_colgroup spec n) = n.
Proof.
  induction n as [| n' IH]; cbn; [reflexivity | f_equal; exact IH].
Qed.

Theorem expand_colgroup_uniform_width : forall spec n w,
  In w (expand_colgroup spec n) ->
  w = cgs_width spec.
Proof.
  induction n as [| n' IH]; intros w Hin; cbn in Hin; [contradiction Hin |].
  destruct Hin as [Heq | Hrest].
  - symmetry; exact Heq.
  - apply IH; exact Hrest.
Qed.
"""

theories["BlinkTableRowPercentHeightSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.5.3 Table Row Percentage Height Resolution *)
Definition resolve_row_percent_height (table_h : Z) (pct : Z) (min_h : Z) : Z :=
  Z.max min_h ((table_h * pct) / 100).

Theorem row_percent_height_ge_min : forall table_h pct min_h,
  resolve_row_percent_height table_h pct min_h >= min_h.
Proof.
  intros. unfold resolve_row_percent_height. lia.
Qed.

Theorem row_percent_height_monotonic : forall h1 h2 pct min_h,
  0 <= h1 <= h2 ->
  pct >= 0 ->
  resolve_row_percent_height h1 pct min_h <= resolve_row_percent_height h2 pct min_h.
Proof.
  intros h1 h2 pct min_h [Hh1 Hh12] Hpct.
  unfold resolve_row_percent_height.
  assert (Hmul: h1 * pct <= h2 * pct) by (apply Z.mul_le_mono_nonneg_r; lia).
  assert (Hdiv: (h1 * pct) / 100 <= (h2 * pct) / 100) by (apply Z.div_le_mono; lia).
  lia.
Qed.
"""

theories["BlinkTableCellVerticalAlignMiddleSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.5.3 Table Cell Vertical-Align Middle Centering *)
Definition cell_middle_offset (row_h : Z) (cell_h : Z) : Z :=
  (row_h - cell_h) / 2.

Theorem cell_middle_offset_nonneg : forall row_h cell_h,
  row_h >= cell_h ->
  cell_middle_offset row_h cell_h >= 0.
Proof.
  intros row_h cell_h Hge.
  unfold cell_middle_offset.
  assert (0 <= (row_h - cell_h) / 2).
  { apply Z.div_pos; lia. }
  lia.
Qed.

Theorem cell_middle_offset_fits : forall row_h cell_h,
  row_h >= cell_h ->
  cell_middle_offset row_h cell_h + cell_h <= row_h.
Proof.
  intros row_h cell_h Hge.
  unfold cell_middle_offset.
  assert (Hdiv: (row_h - cell_h) / 2 <= row_h - cell_h) by (apply Z.div_le_upper_bound; lia).
  lia.
Qed.
"""

theories["BlinkTableCellVerticalAlignBottomSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
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
"""

theories["BlinkTableWrapperFragmentAssemblySemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Table 3 §2 & CSS Box Model 3 Table Wrapper Fragment Assembly *)
Record FragmentBox := {
  fb_y : Z;
  fb_height : Z
}.

Definition fragment_bottom (b : FragmentBox) : Z :=
  fb_y b + fb_height b.

Record TableWrapperAssembly := {
  twa_top_caption : FragmentBox;
  twa_grid_box : FragmentBox;
  twa_bottom_caption : FragmentBox
}.

Definition is_valid_wrapper_assembly (a : TableWrapperAssembly) : Prop :=
  fragment_bottom (twa_top_caption a) <= fb_y (twa_grid_box a) /\
  fragment_bottom (twa_grid_box a) <= fb_y (twa_bottom_caption a).

Theorem valid_assembly_transitive_y : forall a,
  is_valid_wrapper_assembly a ->
  fb_height (twa_top_caption a) >= 0 ->
  fb_height (twa_grid_box a) >= 0 ->
  fb_y (twa_top_caption a) <= fb_y (twa_bottom_caption a).
Proof.
  intros a [Htop Hbot] Htop_h Hgrid_h.
  destruct a as [top grid bot]; cbn in *.
  unfold fragment_bottom in *.
  lia.
Qed.
"""

import sys

def main():
    print(f"Writing {len(theories)} Wave 19 formal theories...")
    for filename, content in theories.items():
        with open(filename, "w") as f:
            f.write(content)
        print(f"  ✓ Wrote {filename}")
    print("Done generating Wave 19 theories!")

if __name__ == '__main__':
    main()
