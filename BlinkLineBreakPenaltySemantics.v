(**
  BlinkLineBreakPenaltySemantics.v
  Formal specification of Chromium Blink optimal line breaking and hyphenation penalty
  derived from third_party/blink/renderer/core/layout/inline/line_breaker.cc and hyphenator.cc
  according to W3C CSS Text Module Level 3 (§5) and Knuth-Plass Penalty Formulation.
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Definition kHyphenPenaltyDefault : Z := 50.
Definition kOrphanPenaltyDefault : Z := 100.

Record LineCandidate := {
  cand_width : Z;
  is_hyphenated : bool;
  is_orphan : bool
}.

Definition compute_line_demerit (cand : LineCandidate) (avail_w : Z) : Z :=
  let delta := avail_w - cand.(cand_width) in
  let badness := delta * delta in
  let hyp_pen := if cand.(is_hyphenated) then kHyphenPenaltyDefault else 0 in
  let orp_pen := if cand.(is_orphan) then kOrphanPenaltyDefault else 0 in
  badness + hyp_pen + orp_pen.

(** 1. Invariant Theorems *)

Theorem line_demerit_nonneg :
  forall (cand : LineCandidate) (avail_w : Z),
    0 <= compute_line_demerit cand avail_w.
Proof.
  intros cand avail_w.
  unfold compute_line_demerit, kHyphenPenaltyDefault, kOrphanPenaltyDefault.
  assert (0 <= (avail_w - cand_width cand) * (avail_w - cand_width cand)).
  {
    destruct (Z_le_gt_dec 0 (avail_w - cand_width cand)).
    - apply Z.mul_nonneg_nonneg; lia.
    - apply Z.mul_nonpos_nonpos; lia.
  }
  destruct (is_hyphenated cand); destruct (is_orphan cand); lia.
Qed.

Theorem perfect_fit_unhyphenated_demerit_zero :
  forall (avail_w : Z),
    let cand := {| cand_width := avail_w; is_hyphenated := false; is_orphan := false |} in
    compute_line_demerit cand avail_w = 0.
Proof.
  intros avail_w cand.
  unfold cand, compute_line_demerit, kHyphenPenaltyDefault, kOrphanPenaltyDefault.
  simpl.
  lia.
Qed.

Theorem hyphenation_increases_demerit :
  forall (w avail_w : Z) (orp : bool),
    let c_plain := {| cand_width := w; is_hyphenated := false; is_orphan := orp |} in
    let c_hyphen := {| cand_width := w; is_hyphenated := true; is_orphan := orp |} in
    compute_line_demerit c_plain avail_w < compute_line_demerit c_hyphen avail_w.
Proof.
  intros w avail_w orp c_plain c_hyphen.
  unfold c_plain, c_hyphen, compute_line_demerit, kHyphenPenaltyDefault.
  simpl.
  destruct orp; lia.
Qed.

Theorem orphan_increases_demerit :
  forall (w avail_w : Z) (hyp : bool),
    let c_plain := {| cand_width := w; is_hyphenated := hyp; is_orphan := false |} in
    let c_orphan := {| cand_width := w; is_hyphenated := hyp; is_orphan := true |} in
    compute_line_demerit c_plain avail_w < compute_line_demerit c_orphan avail_w.
Proof.
  intros w avail_w hyp c_plain c_orphan.
  unfold c_plain, c_orphan, compute_line_demerit, kOrphanPenaltyDefault.
  simpl.
  destruct hyp; lia.
Qed.

