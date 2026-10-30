#!/usr/bin/env python3
"""
create_wave20_theories.py - Generate the 16 formal Coq theories for Wave 20 (CSS Box Model & Intrinsic Sizing).
Theories 252 to 267. Strictly 0 admits. Fully executable.
"""

theories = {}

theories["BlinkInlineMarginAutoSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.3.3 Inline Auto Margin Distribution *)
Definition compute_inline_auto_margin (cb_w : Z) (used_w : Z) : Z :=
  if cb_w <=? used_w then 0
  else (cb_w - used_w) / 2.

Theorem auto_margin_nonneg : forall cb_w used_w,
  compute_inline_auto_margin cb_w used_w >= 0.
Proof.
  intros cb_w used_w.
  unfold compute_inline_auto_margin.
  destruct (cb_w <=? used_w) eqn:E.
  - lia.
  - apply Z.leb_gt in E.
    assert (0 <= (cb_w - used_w) / 2).
    { apply Z.div_le_lower_bound; lia. }
    lia.
Qed.

Theorem auto_margins_fit : forall cb_w used_w,
  used_w >= 0 ->
  compute_inline_auto_margin cb_w used_w + used_w + compute_inline_auto_margin cb_w used_w <= Z.max cb_w used_w.
Proof.
  intros cb_w used_w Hu.
  unfold compute_inline_auto_margin.
  destruct (cb_w <=? used_w) eqn:E.
  - apply Z.leb_le in E. lia.
  - apply Z.leb_gt in E.
    assert (Hdiv: 2 * ((cb_w - used_w) / 2) <= cb_w - used_w).
    { assert (Hrem: 0 <= (cb_w - used_w) mod 2 < 2) by (apply Z.mod_pos_bound; lia).
      assert (Heq: (cb_w - used_w) = 2 * ((cb_w - used_w) / 2) + (cb_w - used_w) mod 2) by (apply Z.div_mod; lia).
      lia. }
    lia.
Qed.
"""

theories["BlinkSelfCollapsingMarginSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §8.3.1 Self-Collapsing Box Margin Strut *)
Record MarginStrut := {
  ms_pos : Z;
  ms_neg : Z
}.

Definition join_self_collapsing_struts (top_s : MarginStrut) (bot_s : MarginStrut) : MarginStrut :=
  {| ms_pos := Z.max (ms_pos top_s) (ms_pos bot_s);
     ms_neg := Z.min (ms_neg top_s) (ms_neg bot_s) |}.

Theorem join_preserves_pos_nonneg : forall top_s bot_s,
  ms_pos top_s >= 0 ->
  ms_pos bot_s >= 0 ->
  ms_pos (join_self_collapsing_struts top_s bot_s) >= 0.
Proof.
  intros top_s bot_s H1 H2.
  cbn.
  apply Z.le_ge.
  apply (Z.le_trans _ (ms_pos top_s)).
  - lia.
  - apply Z.le_max_l.
Qed.

Theorem join_preserves_neg_nonpos : forall top_s bot_s,
  ms_neg top_s <= 0 ->
  ms_neg bot_s <= 0 ->
  ms_neg (join_self_collapsing_struts top_s bot_s) <= 0.
Proof.
  intros top_s bot_s H1 H2.
  cbn.
  apply (Z.le_trans _ (ms_neg top_s)).
  - apply Z.le_min_l.
  - lia.
Qed.
"""

theories["BlinkBoxSizingBorderBoxSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Box Sizing 3 §3 Border-Box Subtraction *)
Definition compute_content_size (border_box_size : Z) (padding_border : Z) : Z :=
  Z.max 0 (border_box_size - padding_border).

Theorem content_size_nonneg : forall bb pb,
  compute_content_size bb pb >= 0.
Proof.
  intros bb pb.
  unfold compute_content_size.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem content_size_exact_when_fits : forall bb pb,
  bb >= pb ->
  pb >= 0 ->
  compute_content_size bb pb + pb = bb.
Proof.
  intros bb pb Hge Hpb.
  unfold compute_content_size.
  assert (bb - pb >= 0) by lia.
  destruct (Z.max_dec 0 (bb - pb)) as [H0 | Hsub]; lia.
Qed.
"""

theories["BlinkPercentPaddingInlineBasisSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Box Model 3 §6 Percentage Padding Resolves Against Inline Size *)
Definition resolve_percent_padding (cb_inline_size : Z) (pct : Z) : Z :=
  (cb_inline_size * pct) / 100.

Theorem percent_padding_nonneg : forall cb_inline pct,
  cb_inline >= 0 ->
  pct >= 0 ->
  resolve_percent_padding cb_inline pct >= 0.
Proof.
  intros cb pct Hcb Hpct.
  unfold resolve_percent_padding.
  assert (0 <= (cb * pct) / 100).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.

Theorem percent_padding_monotonic : forall cb1 cb2 pct,
  0 <= cb1 <= cb2 ->
  pct >= 0 ->
  resolve_percent_padding cb1 pct <= resolve_percent_padding cb2 pct.
Proof.
  intros cb1 cb2 pct [Hcb1 Hcb12] Hpct.
  unfold resolve_percent_padding.
  assert (Hmul: cb1 * pct <= cb2 * pct) by (apply Z.mul_le_mono_nonneg_r; lia).
  apply Z.div_le_mono; lia.
Qed.
"""

theories["BlinkMinContentTextRunSemantics.v"] = r"""From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Sizing 3 §4 Min-Content of Unbroken Text Run *)
Fixpoint sum_glyphs (run : list Z) : Z :=
  match run with
  | nil => 0
  | g :: rest => g + sum_glyphs rest
  end.

Definition min_content_text_run (run : list Z) : Z :=
  sum_glyphs run.

Theorem min_content_text_run_nonneg : forall run,
  (forall g, In g run -> g >= 0) ->
  min_content_text_run run >= 0.
Proof.
  induction run as [| g rest IH]; intros Hpos; cbn; [lia |].
  assert (Hg: g >= 0) by (apply Hpos; left; reflexivity).
  assert (Hrest: sum_glyphs rest >= 0).
  { apply IH. intros x Hx; apply Hpos; right; exact Hx. }
  lia.
Qed.

Theorem min_content_text_run_app : forall r1 r2,
  min_content_text_run (r1 ++ r2) = min_content_text_run r1 + min_content_text_run r2.
Proof.
  induction r1 as [| g rest IH]; intros r2; cbn; [reflexivity |].
  unfold min_content_text_run in *. cbn.
  rewrite IH. lia.
Qed.
"""

theories["BlinkMaxContentSoftHyphenSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Sizing 3 §4 Max-Content of Soft-Hyphenated Word *)
Record HyphenatedWordMetrics := {
  hwm_prefix_w : Z;
  hwm_suffix_w : Z;
  hwm_hyphen_w : Z
}.

Definition word_max_content (m : HyphenatedWordMetrics) : Z :=
  hwm_prefix_w m + hwm_suffix_w m.

Definition word_min_content (m : HyphenatedWordMetrics) : Z :=
  Z.max (hwm_prefix_w m + hwm_hyphen_w m) (hwm_suffix_w m).

Theorem max_content_ge_prefix : forall m,
  hwm_suffix_w m >= 0 ->
  word_max_content m >= hwm_prefix_w m.
Proof.
  intros m Hsuff. unfold word_max_content. lia.
Qed.

Theorem max_content_ge_suffix : forall m,
  hwm_prefix_w m >= 0 ->
  word_max_content m >= hwm_suffix_w m.
Proof.
  intros m Hpref. unfold word_max_content. lia.
Qed.
"""

theories["BlinkReplacedAspectRatioSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Sizing 3 §5.2 Replaced Element Aspect Ratio *)
Definition compute_replaced_height (w : Z) (ratio_w : Z) (ratio_h : Z) : Z :=
  if ratio_w <=? 0 then 0
  else (w * ratio_h) / ratio_w.

Theorem replaced_height_nonneg : forall w rw rh,
  w >= 0 ->
  rw > 0 ->
  rh >= 0 ->
  compute_replaced_height w rw rh >= 0.
Proof.
  intros w rw rh Hw Hrw Hrh.
  unfold compute_replaced_height.
  destruct (rw <=? 0) eqn:E.
  - apply Z.leb_le in E. lia.
  - assert (0 <= (w * rh) / rw).
    { apply Z.div_le_lower_bound; lia. }
    lia.
Qed.

Theorem replaced_height_monotonic : forall w1 w2 rw rh,
  0 <= w1 <= w2 ->
  rw > 0 ->
  rh >= 0 ->
  compute_replaced_height w1 rw rh <= compute_replaced_height w2 rw rh.
Proof.
  intros w1 w2 rw rh [Hw1 Hw12] Hrw Hrh.
  unfold compute_replaced_height.
  destruct (rw <=? 0) eqn:E.
  - apply Z.leb_le in E. lia.
  - assert (Hmul: w1 * rh <= w2 * rh) by (apply Z.mul_le_mono_nonneg_r; lia).
    apply Z.div_le_mono; lia.
Qed.
"""

theories["BlinkInlineBlockBaselineOverflowSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.8.1 Inline-Block Baseline with Overflow != Visible *)
Inductive OverflowMode :=
  | OF_Visible
  | OF_Hidden
  | OF_Scroll
  | OF_Auto.

Definition compute_inline_block_baseline (mode : OverflowMode) (line_box_baseline : option Z) (margin_box_bottom : Z) : Z :=
  match mode with
  | OF_Visible =>
      match line_box_baseline with
      | Some b => b
      | None => margin_box_bottom
      end
  | _ => margin_box_bottom
  end.

Theorem non_visible_overflow_uses_margin_box_bottom : forall mode lbb mbb,
  mode <> OF_Visible ->
  compute_inline_block_baseline mode lbb mbb = mbb.
Proof.
  intros mode lbb mbb Hneq.
  unfold compute_inline_block_baseline.
  destruct mode; [contradiction Hneq; reflexivity | reflexivity | reflexivity | reflexivity].
Qed.
"""

theories["BlinkPercentMarginInlineBasisSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Box Model 3 §7 Percentage Margin Resolves Against Inline Size *)
Definition resolve_percent_margin (cb_inline_size : Z) (pct : Z) : Z :=
  (cb_inline_size * pct) / 100.

Theorem percent_margin_nonneg : forall cb_inline pct,
  cb_inline >= 0 ->
  pct >= 0 ->
  resolve_percent_margin cb_inline pct >= 0.
Proof.
  intros cb pct Hcb Hpct.
  unfold resolve_percent_margin.
  assert (0 <= (cb * pct) / 100).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.

Theorem percent_margin_monotonic : forall cb1 cb2 pct,
  0 <= cb1 <= cb2 ->
  pct >= 0 ->
  resolve_percent_margin cb1 pct <= resolve_percent_margin cb2 pct.
Proof.
  intros cb1 cb2 pct [Hcb1 Hcb12] Hpct.
  unfold resolve_percent_margin.
  assert (Hmul: cb1 * pct <= cb2 * pct) by (apply Z.mul_le_mono_nonneg_r; lia).
  apply Z.div_le_mono; lia.
Qed.
"""

theories["BlinkFitContentClampSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Sizing 3 §4 Fit-Content Clamping Formula *)
Definition fit_content_clamp (min_c : Z) (max_c : Z) (avail : Z) : Z :=
  Z.max min_c (Z.min max_c avail).

Theorem fit_content_ge_min : forall min_c max_c avail,
  fit_content_clamp min_c max_c avail >= min_c.
Proof.
  intros. unfold fit_content_clamp.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem fit_content_le_max : forall min_c max_c avail,
  min_c <= max_c ->
  fit_content_clamp min_c max_c avail <= max_c.
Proof.
  intros min_c max_c avail Hle.
  unfold fit_content_clamp.
  assert (Z.min max_c avail <= max_c) by (apply Z.le_min_l).
  destruct (Z.max_dec min_c (Z.min max_c avail)) as [Hmax | Hmin]; lia.
Qed.

Theorem fit_content_exact_when_within : forall min_c max_c avail,
  min_c <= avail <= max_c ->
  fit_content_clamp min_c max_c avail = avail.
Proof.
  intros min_c max_c avail [H1 H2].
  unfold fit_content_clamp.
  assert (Hmin: Z.min max_c avail = avail).
  { destruct (Z.min_dec max_c avail); lia. }
  rewrite Hmin.
  destruct (Z.max_dec min_c avail); lia.
Qed.
"""

theories["BlinkMinOverridesMaxSizingSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.4 Min-Size Overrides Max-Size *)
Definition resolve_min_max_clamping (min_size : Z) (max_size : Z) (target : Z) : Z :=
  Z.max min_size (Z.min max_size target).

Theorem min_size_unconditionally_respected : forall min_s max_s target,
  resolve_min_max_clamping min_s max_s target >= min_s.
Proof.
  intros. unfold resolve_min_max_clamping.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem max_size_respected_when_consistent : forall min_s max_s target,
  min_s <= max_s ->
  resolve_min_max_clamping min_s max_s target <= max_s.
Proof.
  intros min_s max_s target Hle.
  unfold resolve_min_max_clamping.
  assert (Z.min max_s target <= max_s) by (apply Z.le_min_l).
  destruct (Z.max_dec min_s (Z.min max_s target)); lia.
Qed.
"""

theories["BlinkBFCMarginIsolationSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §8.3.1 BFC Root Margin Non-Collapsing Boundary *)
Record BFCContainer := {
  bfc_border_padding_top : Z;
  bfc_child_margin_top : Z;
  bfc_child_height : Z;
  bfc_border_padding_bottom : Z
}.

Definition bfc_total_block_size (c : BFCContainer) : Z :=
  bfc_border_padding_top c + bfc_child_margin_top c + bfc_child_height c + bfc_border_padding_bottom c.

Theorem bfc_contains_child_margin : forall c,
  bfc_border_padding_top c >= 0 ->
  bfc_child_margin_top c >= 0 ->
  bfc_child_height c >= 0 ->
  bfc_border_padding_bottom c >= 0 ->
  bfc_total_block_size c >= bfc_child_margin_top c.
Proof.
  intros [bp_t cm_t ch bp_b] H1 H2 H3 H4.
  cbn in *. unfold bfc_total_block_size; cbn.
  lia.
Qed.
"""

theories["BlinkNegativeMarginAlgebraSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §8.3.1 Negative Margin Collapsing Algebra *)
Definition collapse_margin_strut (pos_m : Z) (neg_m : Z) : Z :=
  pos_m + neg_m.

Theorem collapsed_margin_bounded : forall pos_m neg_m,
  pos_m >= 0 ->
  neg_m <= 0 ->
  neg_m <= collapse_margin_strut pos_m neg_m <= pos_m.
Proof.
  intros pos_m neg_m Hpos Hneg.
  unfold collapse_margin_strut. lia.
Qed.

Theorem collapsed_margin_zero_neg : forall pos_m,
  collapse_margin_strut pos_m 0 = pos_m.
Proof.
  intros. unfold collapse_margin_strut. lia.
Qed.
"""

theories["BlinkOverflowClipGeometrySemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Overflow 3 §3 1D Overflow Clip Geometry *)
Definition intersect_interval (x1 r1 x2 r2 : Z) : Z * Z :=
  let left := Z.max x1 x2 in
  let right := Z.min r1 r2 in
  if left <=? right then (left, right)
  else (left, left).

Theorem intersect_interval_contained_left : forall x1 r1 x2 r2,
  let '(l, r) := intersect_interval x1 r1 x2 r2 in
  l >= x1 \/ l >= x2.
Proof.
  intros x1 r1 x2 r2.
  unfold intersect_interval.
  destruct (Z.max x1 x2 <=? Z.min r1 r2) eqn:E;
  assert (Z.max x1 x2 >= x1) by (apply Z.le_ge; apply Z.le_max_l);
  lia.
Qed.

Theorem intersect_interval_valid_range : forall x1 r1 x2 r2,
  let '(l, r) := intersect_interval x1 r1 x2 r2 in
  l <= r.
Proof.
  intros x1 r1 x2 r2.
  unfold intersect_interval.
  destruct (Z.max x1 x2 <=? Z.min r1 r2) eqn:E.
  - apply Z.leb_le in E. lia.
  - lia.
Qed.
"""

theories["BlinkBoxStrutMappingSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Writing Modes 3 §4 Logical to Physical Box Strut Mapping *)
Record LogicalBoxStrut := {
  lbs_inline_start : Z;
  lbs_inline_end : Z;
  lbs_block_start : Z;
  lbs_block_end : Z
}.

Record PhysicalBoxStrut := {
  pbs_top : Z;
  pbs_right : Z;
  pbs_bottom : Z;
  pbs_left : Z
}.

Definition map_strut_horizontal_tb (s : LogicalBoxStrut) : PhysicalBoxStrut :=
  {| pbs_top := lbs_block_start s;
     pbs_bottom := lbs_block_end s;
     pbs_left := lbs_inline_start s;
     pbs_right := lbs_inline_end s |}.

Theorem strut_horizontal_tb_inline_sum_conserved : forall s,
  pbs_left (map_strut_horizontal_tb s) + pbs_right (map_strut_horizontal_tb s) =
  lbs_inline_start s + lbs_inline_end s.
Proof.
  intros [ins ie bs be]; cbn. reflexivity.
Qed.

Theorem strut_horizontal_tb_block_sum_conserved : forall s,
  pbs_top (map_strut_horizontal_tb s) + pbs_bottom (map_strut_horizontal_tb s) =
  lbs_block_start s + lbs_block_end s.
Proof.
  intros [ins ie bs be]; cbn. reflexivity.
Qed.
"""

theories["BlinkIndefinitePercentHeightSemantics.v"] = r"""From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.5 Indefinite Percentage Height Resolution *)
Definition resolve_percent_height_with_indefinite (cb_height : option Z) (pct : Z) (content_h : Z) : Z :=
  match cb_height with
  | Some h => (h * pct) / 100
  | None => content_h
  end.

Theorem indefinite_resolves_to_content : forall pct content_h,
  resolve_percent_height_with_indefinite None pct content_h = content_h.
Proof.
  intros. unfold resolve_percent_height_with_indefinite. reflexivity.
Qed.

Theorem definite_nonneg : forall h pct content_h,
  h >= 0 ->
  pct >= 0 ->
  resolve_percent_height_with_indefinite (Some h) pct content_h >= 0.
Proof.
  intros h pct content_h Hh Hpct.
  unfold resolve_percent_height_with_indefinite.
  assert (0 <= (h * pct) / 100).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.
"""

import sys

def main():
    print(f"Writing {len(theories)} Wave 20 formal theories...")
    for filename, content in theories.items():
        with open(filename, "w") as f:
            f.write(content)
        print(f"  ✓ Wrote {filename}")
    print("Done generating Wave 20 theories!")

if __name__ == '__main__':
    main()
