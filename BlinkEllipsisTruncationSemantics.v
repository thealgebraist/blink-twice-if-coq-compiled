(**
  BlinkEllipsisTruncationSemantics.v
  Formal specification of Chromium Blink inline box text overflow and ellipsis truncation
  derived from third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc (TruncateLine)
  and line_truncator.cc
  according to W3C CSS Overflow Module Level 3 (§3.1 text-overflow: ellipsis).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record LineItem := {
  item_id : Z;
  item_width : Z
}.

(** 1. Backward Truncation Walk *)

Fixpoint truncate_items_prefix
    (target_w : Z) (current_w : Z) (items : list LineItem) : list LineItem :=
  match items with
  | [] => []
  | it :: rest =>
      if current_w + it.(item_width) <=? target_w then
        it :: truncate_items_prefix target_w (current_w + it.(item_width)) rest
      else
        []
  end.

Definition sum_item_widths (items : list LineItem) : Z :=
  fold_right (fun it acc => it.(item_width) + acc) 0 items.

Lemma sum_item_widths_cons :
  forall it rest,
    sum_item_widths (it :: rest) = it.(item_width) + sum_item_widths rest.
Proof.
  intros. reflexivity.
Qed.

Definition compute_truncated_line_width
    (items : list LineItem) (ellipsis_w : Z) (avail_w : Z) : Z :=
  let target_w := Z.max 0 (avail_w - ellipsis_w) in
  let visible_items := truncate_items_prefix target_w 0 items in
  sum_item_widths visible_items + ellipsis_w.

(** 2. Invariant Theorems *)

Lemma truncate_prefix_accumulates_bounded :
  forall (items : list LineItem) (target_w current_w : Z),
    (forall it, In it items -> 0 <= it.(item_width)) ->
    0 <= current_w ->
    current_w <= target_w ->
    sum_item_widths (truncate_items_prefix target_w current_w items) + current_w <= target_w.
Proof.
  induction items as [|it rest IH].
  - intros target_w current_w Hw Hpos Hle.
    simpl.
    unfold sum_item_widths. simpl. lia.
  - intros target_w current_w Hw Hpos Hle.
    simpl.
    destruct (current_w + it.(item_width) <=? target_w) eqn:Efit.
    + apply Z.leb_le in Efit.
      rewrite sum_item_widths_cons.
      assert (Hpos_it : 0 <= it.(item_width)).
      { apply Hw. simpl. left. reflexivity. }
      assert (Hrec : sum_item_widths (truncate_items_prefix target_w (current_w + it.(item_width)) rest) +
                     (current_w + it.(item_width)) <= target_w).
      {
        apply IH.
        - intros item Hin. apply Hw. simpl. right. exact Hin.
        - lia.
        - exact Efit.
      }
      lia.
    + unfold sum_item_widths. simpl. lia.
Qed.

Theorem truncated_line_fits_in_available_space :
  forall (items : list LineItem) (ellipsis_w avail_w : Z),
    (forall it, In it items -> 0 <= it.(item_width)) ->
    ellipsis_w <= avail_w ->
    0 <= ellipsis_w ->
    compute_truncated_line_width items ellipsis_w avail_w <= avail_w.
Proof.
  intros items ellipsis_w avail_w Hw Hfit Hell_pos.
  unfold compute_truncated_line_width.
  assert (Htarget : Z.max 0 (avail_w - ellipsis_w) = avail_w - ellipsis_w) by lia.
  rewrite Htarget.
  pose proof (truncate_prefix_accumulates_bounded items (avail_w - ellipsis_w) 0) as Hbound.
  assert (0 <= 0) by lia.
  assert (0 <= avail_w - ellipsis_w) by lia.
  specialize (Hbound Hw H H0).
  lia.
Qed.

Theorem truncated_item_count_le_original :
  forall (items : list LineItem) (target_w current_w : Z),
    (length (truncate_items_prefix target_w current_w items) <= length items)%nat.
Proof.
  induction items as [|it rest IH].
  - intros target_w current_w. simpl. lia.
  - intros target_w current_w.
    simpl.
    destruct (current_w + it.(item_width) <=? target_w).
    + simpl. specialize (IH target_w (current_w + it.(item_width))). lia.
    + simpl. lia.
Qed.
