(******************************************************************************)
(* BlinkBaselineAlignmentSemantics.v                                          *)
(* Sound Formal Specification for CSS Box Alignment Baseline Sharing Groups  *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Box Alignment Module Level 3 (§9 Baseline Alignment)            *)
(* 2. Blink BaselineUtils (`baseline_utils.cc`) & BoxFragment                 *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Import ListNotations.
Open Scope Z_scope.

Record BaselineItem := mkBaselineItem {
  bi_ascent : Z;
  bi_descent : Z
}.

Record BaselineGroupResult := mkBaselineGroupResult {
  bgr_max_ascent : Z;
  bgr_max_descent : Z;
  bgr_total_height : Z
}.

Fixpoint compute_baseline_group (items : list BaselineItem) : BaselineGroupResult :=
  match items with
  | [] => mkBaselineGroupResult 0 0 0
  | it :: rest =>
      let res := compute_baseline_group rest in
      let ma := Z.max (bi_ascent it) (bgr_max_ascent res) in
      let md := Z.max (bi_descent it) (bgr_max_descent res) in
      mkBaselineGroupResult ma md (sat_clamp (ma + md))
  end.

Definition compute_item_baseline_shift (group_ascent : Z) (item_ascent : Z) : Z :=
  Z.max 0 (group_ascent - item_ascent).

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem baseline_shift_nonneg :
  forall ga ia,
    0 <= compute_item_baseline_shift ga ia.
Proof.
  intros ga ia. unfold compute_item_baseline_shift. apply Z.le_max_l.
Qed.

Theorem baseline_group_bounds_items :
  forall items it,
    In it items ->
    bi_ascent it <= bgr_max_ascent (compute_baseline_group items) /\
    bi_descent it <= bgr_max_descent (compute_baseline_group items).
Proof.
  induction items as [| x rest IH]; intros it Hin.
  - simpl in Hin. contradiction.
  - simpl. destruct Hin as [Heq | Hin_rest].
    + subst it. simpl. split; apply Z.le_max_l.
    + specialize (IH it Hin_rest).
      destruct IH as [Ha Hd].
      split.
      * eapply Z.le_trans; [exact Ha | apply Z.le_max_r].
      * eapply Z.le_trans; [exact Hd | apply Z.le_max_r].
Qed.

Theorem baseline_group_deterministic :
  forall items r1 r2,
    r1 = compute_baseline_group items ->
    r2 = compute_baseline_group items ->
    r1 = r2.
Proof.
  intros items r1 r2 H1 H2. subst. reflexivity.
Qed.
