#!/usr/bin/env python3
"""
create_wave29_theories.py - Generate 16 formal Coq theories for Wave 29 with strictly 0 admits.
Theme: Blink MathML Core Layout Semantics
"""

theories = {
    "BlinkMathMLDisplayModeSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Display Mode Semantics *)
(** MathML Core §2.1: math display block vs inline display modes *)

Inductive MathMLDisplayMode :=
  | MathMLDisplayInline
  | MathMLDisplayBlock.

Definition is_block_math (m : MathMLDisplayMode) : bool :=
  match m with
  | MathMLDisplayBlock => true
  | MathMLDisplayInline => false
  end.

Theorem block_display_is_block :
  is_block_math MathMLDisplayBlock = true.
Proof.
  reflexivity.
Qed.

Theorem inline_display_is_not_block :
  is_block_math MathMLDisplayInline = false.
Proof.
  reflexivity.
Qed.
""",

    "BlinkMathMLTokenElementSizingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Token Element Font Style Semantics *)
(** MathML Core §3.2: single-char mi italic vs multi-char normal *)

Inductive FontStyle :=
  | StyleItalic
  | StyleNormal.

Definition resolve_mi_font_style (char_count : Z) : FontStyle :=
  if char_count =? 1 then StyleItalic
  else StyleNormal.

Theorem single_char_mi_is_italic :
  resolve_mi_font_style 1 = StyleItalic.
Proof.
  unfold resolve_mi_font_style; reflexivity.
Qed.

Theorem multi_char_mi_is_normal : forall n,
  1 < n ->
  resolve_mi_font_style n = StyleNormal.
Proof.
  intros n Hgt.
  unfold resolve_mi_font_style.
  assert (n =? 1 = false) by (apply Z.eqb_neq; lia).
  rewrite H; reflexivity.
Qed.
""",

    "BlinkMathMLFractionBarThicknessSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Fraction Bar Thickness Semantics *)
(** MathML Core §3.3.2: fraction bar thickness >= 1 *)

Definition resolve_fraction_bar_thickness (raw_rule_thickness : Z) : Z :=
  Z.max 1 raw_rule_thickness.

Theorem fraction_bar_thickness_strictly_positive : forall raw,
  0 < resolve_fraction_bar_thickness raw.
Proof.
  intros raw.
  unfold resolve_fraction_bar_thickness.
  lia.
Qed.
""",

    "BlinkMathMLFractionGapClearanceSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Fraction Gap Clearance Semantics *)
(** MathML Core §3.3.2: gap clearance >= min_gap *)

Definition compute_fraction_total_gap (gap_above gap_below min_gap : Z) : Z :=
  Z.max min_gap gap_above + Z.max min_gap gap_below.

Theorem fraction_total_gap_at_least_double_min : forall ga gb min_gap,
  0 <= min_gap ->
  2 * min_gap <= compute_fraction_total_gap ga gb min_gap.
Proof.
  intros ga gb min_gap Hmin.
  unfold compute_fraction_total_gap.
  lia.
Qed.
""",

    "BlinkMathMLSuperscriptShiftSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Superscript Shift Semantics *)
(** MathML Core §3.4.1: superscript baseline shift >= min_shift *)

Definition resolve_superscript_shift (desired_shift min_shift : Z) : Z :=
  Z.max (Z.max 0 min_shift) desired_shift.

Theorem superscript_shift_ge_min : forall des min_s,
  0 <= min_s ->
  min_s <= resolve_superscript_shift des min_s.
Proof.
  intros des min_s Hmin.
  unfold resolve_superscript_shift.
  lia.
Qed.
""",

    "BlinkMathMLSubscriptDropSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Subscript Drop Semantics *)
(** MathML Core §3.4.1: subscript baseline drop >= min_drop *)

Definition resolve_subscript_drop (desired_drop min_drop : Z) : Z :=
  Z.max (Z.max 0 min_drop) desired_drop.

Theorem subscript_drop_ge_min : forall des min_d,
  0 <= min_d ->
  min_d <= resolve_subscript_drop des min_d.
Proof.
  intros des min_d Hmin.
  unfold resolve_subscript_drop.
  lia.
Qed.
""",

    "BlinkMathMLSubSupGapDisjointnessSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML SubSup Gap Clearance Semantics *)
(** MathML Core §3.4.1: gap clearance between scripts *)

Definition compute_subsup_gap (sup_bottom sub_top : Z) : Z :=
  sup_bottom - sub_top.

Theorem subsup_gap_positive_implies_disjoint : forall sup_b sub_t,
  0 < compute_subsup_gap sup_b sub_t ->
  sub_t < sup_b.
Proof.
  intros sup_b sub_t Hgap.
  unfold compute_subsup_gap in Hgap.
  lia.
Qed.
""",

    "BlinkMathMLUnderOverCenteringSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML UnderOver Horizontal Centering Semantics *)
(** MathML Core §3.5: script centered over base *)

Definition compute_underover_centering_offset (base_width script_width : Z) : Z :=
  (base_width - script_width) / 2.

Theorem centering_symmetric_for_equal_widths : forall w,
  compute_underover_centering_offset w w = 0.
Proof.
  intros w.
  unfold compute_underover_centering_offset.
  assert (w - w = 0) by lia.
  rewrite H; reflexivity.
Qed.
""",

    "BlinkMathMLUnderOverGapSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML UnderOver Vertical Gap Semantics *)
(** MathML Core §3.5: vertical gap clearance *)

Definition resolve_underover_vertical_gap (gap min_gap : Z) : Z :=
  Z.max (Z.max 0 min_gap) gap.

Theorem underover_gap_bounded_below : forall g min_g,
  0 <= min_g ->
  min_g <= resolve_underover_vertical_gap g min_g.
Proof.
  intros g min_g Hmin.
  unfold resolve_underover_vertical_gap; lia.
Qed.
""",

    "BlinkMathMLUnderOverLimitsBoundingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Munderover Height Bounding Semantics *)
(** MathML Core §3.5: total height accumulation *)

Definition compute_munderover_total_height (under_h base_h over_h gap1 gap2 : Z) : Z :=
  Z.max 0 under_h + Z.max 0 base_h + Z.max 0 over_h + Z.max 0 gap1 + Z.max 0 gap2.

Theorem munderover_height_ge_base : forall uh bh oh g1 g2,
  0 <= bh ->
  bh <= compute_munderover_total_height uh bh oh g1 g2.
Proof.
  intros uh bh oh g1 g2 Hbh.
  unfold compute_munderover_total_height; lia.
Qed.
""",

    "BlinkMathMLRadicalSymbolSizingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Radical Symbol Sizing Semantics *)
(** MathML Core §3.6.1: radical height coverage *)

Definition compute_radical_symbol_height (radicand_height vertical_gap rule_thickness : Z) : Z :=
  Z.max 0 radicand_height + Z.max 0 vertical_gap + Z.max 1 rule_thickness.

Theorem radical_height_covers_radicand : forall rh vg rt,
  0 <= rh ->
  rh < compute_radical_symbol_height rh vg rt.
Proof.
  intros rh vg rt Hrh.
  unfold compute_radical_symbol_height; lia.
Qed.
""",

    "BlinkMathMLRootIndexPositioningSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Root Index Positioning Semantics *)
(** MathML Core §3.6.2: mroot index notch positioning *)

Record RadicalNotch := {
  notch_x : Z;
  notch_y : Z
}.

Definition position_root_index (notch : RadicalNotch) (index_w index_h : Z) : RadicalNotch :=
  {| notch_x := notch_x notch;
     notch_y := notch_y notch - Z.max 0 index_h |}.

Theorem root_index_y_above_notch : forall notch w h,
  0 <= h ->
  notch_y (position_root_index notch w h) <= notch_y notch.
Proof.
  intros notch w h Hh.
  unfold position_root_index; simpl; lia.
Qed.
""",

    "BlinkMathMLOperatorVerticalStretchingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Operator Vertical Stretching Semantics *)
(** MathML Core §3.2.4: stretchy operator coverage *)

Definition stretch_operator_height (intrinsic_height target_height : Z) : Z :=
  Z.max (Z.max 0 intrinsic_height) (Z.max 0 target_height).

Theorem stretched_operator_covers_target : forall ih th,
  0 <= th ->
  th <= stretch_operator_height ih th.
Proof.
  intros ih th Hth.
  unfold stretch_operator_height; lia.
Qed.
""",

    "BlinkMathMLOperatorHorizontalStretchingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Operator Horizontal Stretching Semantics *)
(** MathML Core §3.2.4: stretchy horizontal operator coverage *)

Definition stretch_operator_width (intrinsic_width target_width : Z) : Z :=
  Z.max (Z.max 0 intrinsic_width) (Z.max 0 target_width).

Theorem stretched_operator_covers_target_width : forall iw tw,
  0 <= tw ->
  tw <= stretch_operator_width iw tw.
Proof.
  intros iw tw Htw.
  unfold stretch_operator_width; lia.
Qed.
""",

    "BlinkMathMLTableGridBaselineSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Table Grid Baseline Alignment Semantics *)
(** MathML Core §3.7: row baseline from max cell ascent *)

Definition compute_row_baseline (cell_ascent1 cell_ascent2 : Z) : Z :=
  Z.max (Z.max 0 cell_ascent1) (Z.max 0 cell_ascent2).

Theorem row_baseline_covers_cell1 : forall ca1 ca2,
  0 <= ca1 ->
  ca1 <= compute_row_baseline ca1 ca2.
Proof.
  intros ca1 ca2 Hca1.
  unfold compute_row_baseline; lia.
Qed.

Theorem row_baseline_covers_cell2 : forall ca1 ca2,
  0 <= ca2 ->
  ca2 <= compute_row_baseline ca1 ca2.
Proof.
  intros ca1 ca2 Hca2.
  unfold compute_row_baseline; lia.
Qed.
""",

    "BlinkMathMLScriptLevelScalingSemantics.v": r"""Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Scriptlevel Font Scaling Semantics *)
(** MathML Core §2.4: size attenuation bounded below *)

Definition scale_font_size_scriptlevel (base_size : Z) (scriptlevel : nat) : Z :=
  match scriptlevel with
  | O => Z.max 1 base_size
  | S O => Z.max 1 (base_size * 71 / 100)
  | S (S _) => Z.max 1 (base_size * 50 / 100)
  end.

Theorem scaled_size_strictly_positive : forall base_size level,
  0 < scale_font_size_scriptlevel base_size level.
Proof.
  intros base_size level.
  unfold scale_font_size_scriptlevel.
  destruct level as [| [| n]]; lia.
Qed.
"""
}

def main():
    print("Writing 16 formal Coq theories for Wave 29...")
    for filename, code in theories.items():
        with open(filename, "w") as f:
            f.write(code)
        print(f"  -> Wrote {filename}")
    print("Wave 29 Coq theories successfully written.")

if __name__ == "__main__":
    main()
