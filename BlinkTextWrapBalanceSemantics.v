(**
  BlinkTextWrapBalanceSemantics.v
  Formal specification of Chromium Blink text-wrap: balance and line break scoring
  derived from third_party/blink/renderer/core/layout/inline/text_wrap_evaluator.cc
  according to W3C CSS Text Module Level 4 (§5.1 text-wrap: balance & Knuth-Plass Penalty Metric).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Line Variance Metric *)

Definition line_deviation_sq (w mean_w : Z) : Z :=
  (w - mean_w) * (w - mean_w).

Theorem line_deviation_sq_nonneg :
  forall w mean_w : Z,
    0 <= line_deviation_sq w mean_w.
Proof.
  intros w mean_w.
  unfold line_deviation_sq.
  destruct (Z_le_gt_dec 0 (w - mean_w)) as [Hpos | Hneg].
  - apply Z.mul_nonneg_nonneg; lia.
  - apply Z.mul_nonpos_nonpos; lia.
Qed.

Theorem line_deviation_sq_zero_iff_equal :
  forall w mean_w : Z,
    line_deviation_sq w mean_w = 0 <-> w = mean_w.
Proof.
  intros w mean_w.
  unfold line_deviation_sq.
  split.
  - intros H.
    apply Z.mul_eq_0 in H.
    destruct H; lia.
  - intros H.
    subst. simpl. lia.
Qed.

Fixpoint sum_line_variances (lines : list Z) (mean_w : Z) : Z :=
  match lines with
  | [] => 0
  | w :: ws => line_deviation_sq w mean_w + sum_line_variances ws mean_w
  end.

Theorem sum_line_variances_nonneg :
  forall (lines : list Z) (mean_w : Z),
    0 <= sum_line_variances lines mean_w.
Proof.
  intros lines mean_w.
  induction lines as [|w ws IH].
  - simpl. lia.
  - cbn [sum_line_variances].
    pose proof (line_deviation_sq_nonneg w mean_w).
    lia.
Qed.

Theorem perfect_balance_zero_variance :
  forall (ws : list Z) (mean_w : Z),
    Forall (fun w => w = mean_w) ws ->
    sum_line_variances ws mean_w = 0.
Proof.
  intros ws mean_w Hfa.
  induction Hfa as [|w rest Heq Hrest IH].
  - reflexivity.
  - cbn [sum_line_variances].
    subst.
    unfold line_deviation_sq.
    assert ((mean_w - mean_w) * (mean_w - mean_w) = 0) by lia.
    rewrite H.
    rewrite IH.
    lia.
Qed.

(** 2. Balanced Line Partitioning Conservation *)

Definition total_word_count (lines : list (list Z)) : Z :=
  fold_right (fun l acc => Z.of_nat (length l) + acc) 0 lines.

Theorem partition_preserves_length :
  forall (l1 l2 : list Z),
    total_word_count [l1; l2] = Z.of_nat (length l1 + length l2)%nat.
Proof.
  intros l1 l2.
  unfold total_word_count.
  cbn [fold_right].
  rewrite Nat2Z.inj_add.
  lia.
Qed.

(** 3. Capacity Bound Enforcement *)

Definition line_fits (w avail_w : Z) : bool :=
  w <=? avail_w.

Definition all_lines_fit (lines : list Z) (avail_w : Z) : bool :=
  forallb (fun w => line_fits w avail_w) lines.

Theorem all_lines_fit_implies_each_fits :
  forall lines avail_w w,
    all_lines_fit lines avail_w = true ->
    In w lines ->
    w <= avail_w.
Proof.
  intros lines avail_w w Hfit Hin.
  unfold all_lines_fit in Hfit.
  apply forallb_forall with (x := w) in Hfit; [|exact Hin].
  unfold line_fits in Hfit.
  apply Z.leb_le in Hfit.
  exact Hfit.
Qed.
