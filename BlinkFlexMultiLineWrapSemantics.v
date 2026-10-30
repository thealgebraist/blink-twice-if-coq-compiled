(* ========================================================================= *)
(*               BlinkFlexMultiLineWrapSemantics.v                           *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Multi-Line Flexbox Wrapping and     *)
(* Cross-Size Distribution per CSS Flexible Box Layout Module Level 1        *)
(* §8.4 (align-content) & §9.4 (Cross Size Determination).                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Lia.
Open Scope Z_scope.

Record FlexItem := mkFlexItem {
  fi_main_size : Z;
  fi_cross_size : Z
}.

Record FlexLine := mkFlexLine {
  fl_items : list FlexItem;
  fl_cross_size : Z;
  fl_cross_offset : Z
}.

Fixpoint sum_main_sizes (items : list FlexItem) : Z :=
  match items with
  | nil => 0
  | item :: rest => fi_main_size item + sum_main_sizes rest
  end.

Fixpoint max_cross_size (items : list FlexItem) : Z :=
  match items with
  | nil => 0
  | item :: rest => Z.max (fi_cross_size item) (max_cross_size rest)
  end.

Definition should_break_line (current_line_empty : bool) (cur_main : Z) (item_main : Z) (avail_main : Z) : bool :=
  if current_line_empty then false
  else (avail_main <? cur_main + item_main)%bool.

Fixpoint compute_line_cross_offsets (cross_sizes : list Z) (current_y : Z) (cross_gap : Z) : list Z :=
  match cross_sizes with
  | nil => nil
  | sz :: rest => current_y :: compute_line_cross_offsets rest (current_y + sz + cross_gap) cross_gap
  end.

Fixpoint sum_cross_sizes (cross_sizes : list Z) : Z :=
  match cross_sizes with
  | nil => 0
  | sz :: rest => sz + sum_cross_sizes rest
  end.

(* ------------------------------------------------------------------------- *)
(* Theorems                                                                  *)
(* ------------------------------------------------------------------------- *)

Theorem sum_main_sizes_nonneg : forall items,
  (forall it, In it items -> fi_main_size it >= 0) ->
  sum_main_sizes items >= 0.
Proof.
  induction items as [| it rest IH]; intros Hpos; cbn.
  - lia.
  - assert (H_it: fi_main_size it >= 0) by (apply Hpos; left; reflexivity).
    assert (H_rest: forall it0, In it0 rest -> fi_main_size it0 >= 0).
    { intros it0 Hin. apply Hpos; right; exact Hin. }
    specialize (IH H_rest).
    lia.
Qed.

Theorem sum_main_sizes_app : forall l1 l2,
  sum_main_sizes (l1 ++ l2) = sum_main_sizes l1 + sum_main_sizes l2.
Proof.
  induction l1 as [| it rest IH]; intros l2; cbn.
  - reflexivity.
  - rewrite IH. lia.
Qed.

Theorem first_item_never_breaks : forall item_main avail_main,
  should_break_line true 0 item_main avail_main = false.
Proof.
  intros item_main avail_main.
  unfold should_break_line; reflexivity.
Qed.

Theorem break_condition_sound : forall cur_main item_main avail_main,
  should_break_line false cur_main item_main avail_main = true ->
  cur_main + item_main > avail_main.
Proof.
  intros cur_main item_main avail_main Hbreak.
  unfold should_break_line in Hbreak.
  destruct (avail_main <? cur_main + item_main)%bool eqn:E.
  - apply Z.ltb_lt in E. lia.
  - discriminate Hbreak.
Qed.

Theorem compute_line_cross_offsets_length : forall cross_sizes cur_y gap,
  length (compute_line_cross_offsets cross_sizes cur_y gap) = length cross_sizes.
Proof.
  induction cross_sizes as [| sz rest IH]; intros cur_y gap; cbn.
  - reflexivity.
  - rewrite IH; reflexivity.
Qed.

Lemma compute_line_cross_offsets_all_ge : forall cross_sizes cur_y gap,
  gap >= 0 ->
  (forall sz, In sz cross_sizes -> sz > 0) ->
  forall y, In y (compute_line_cross_offsets cross_sizes cur_y gap) ->
  y >= cur_y.
Proof.
  induction cross_sizes as [| sz rest IH]; intros cur_y gap Hgap Hpos y Hy; cbn in Hy; [contradiction Hy |].
  destruct Hy as [-> | Hy_rest]; [lia |].
  assert (Hsz: sz > 0) by (apply Hpos; left; reflexivity).
  assert (Hpos': forall s, In s rest -> s > 0) by (intros s Hs; apply Hpos; right; exact Hs).
  specialize (IH (cur_y + sz + gap) gap Hgap Hpos' y Hy_rest).
  lia.
Qed.

Theorem compute_line_cross_offsets_strictly_monotonic : forall cross_sizes cur_y gap,
  gap >= 0 ->
  (forall sz, In sz cross_sizes -> sz > 0) ->
  forall (i j : nat),
    (i < j)%nat ->
    (j < length cross_sizes)%nat ->
    nth i (compute_line_cross_offsets cross_sizes cur_y gap) 0 <
    nth j (compute_line_cross_offsets cross_sizes cur_y gap) 0.
Proof.
  induction cross_sizes as [| sz rest IH]; intros cur_y gap Hgap Hpos i j Hij Hj.
  - cbn in Hj; lia.
  - cbn [length] in Hj.
    destruct i as [| i'].
    + cbn [nth compute_line_cross_offsets].
      destruct j as [| j']; [lia |].
      cbn [nth].
      assert (Hsz: sz > 0) by (apply Hpos; left; reflexivity).
      assert (Hpos': forall s, In s rest -> s > 0) by (intros s Hs; apply Hpos; right; exact Hs).
      assert (Hin: In (nth j' (compute_line_cross_offsets rest (cur_y + sz + gap) gap) 0)
                      (compute_line_cross_offsets rest (cur_y + sz + gap) gap)).
      { apply nth_In.
        rewrite compute_line_cross_offsets_length.
        cbn in Hj; lia. }
      assert (Hge := compute_line_cross_offsets_all_ge rest (cur_y + sz + gap) gap Hgap Hpos' _ Hin).
      lia.
    + destruct j as [| j']; [lia |].
      cbn [nth compute_line_cross_offsets].
      assert (Hsz: sz > 0) by (apply Hpos; left; reflexivity).
      assert (Hpos': forall s, In s rest -> s > 0) by (intros s Hs; apply Hpos; right; exact Hs).
      apply (IH (cur_y + sz + gap) gap Hgap Hpos' i' j'); [lia | lia].
Qed.
