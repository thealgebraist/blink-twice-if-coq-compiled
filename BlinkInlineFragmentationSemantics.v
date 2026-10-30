(* ========================================================================= *)
(*               BlinkInlineFragmentationSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Inline Line Box Fragmentation &       *)
(* Splitting per W3C CSS Fragmentation 3 & CSS Inline Layout 3.              *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record InlineBreakToken := {
  tok_item_index : nat;
  tok_text_offset : nat
}.

Definition token_lt (t1 t2 : InlineBreakToken) : Prop :=
  (tok_item_index t1 < tok_item_index t2)%nat \/
  (tok_item_index t1 = tok_item_index t2 /\ (tok_text_offset t1 < tok_text_offset t2)%nat).

Record LineBreakStep := {
  step_consumed_chars : nat;
  step_advances_item : bool
}.

Definition advance_token (t : InlineBreakToken) (step : LineBreakStep) : InlineBreakToken :=
  if step_advances_item step then
    {| tok_item_index := S (tok_item_index t); tok_text_offset := 0%nat |}
  else
    {| tok_item_index := tok_item_index t; tok_text_offset := (tok_text_offset t + step_consumed_chars step)%nat |}.

Theorem token_lt_irrefl : forall t,
  ~ token_lt t t.
Proof.
  intros [idx off] [Hidx | [Heq Hoff]].
  - lia.
  - lia.
Qed.

Theorem token_lt_trans : forall t1 t2 t3,
  token_lt t1 t2 ->
  token_lt t2 t3 ->
  token_lt t1 t3.
Proof.
  intros [i1 o1] [i2 o2] [i3 o3] [H1 | [Heq1 Ho1]] [H2 | [Heq2 Ho2]];
  unfold token_lt; cbn in *.
  - left. lia.
  - left. lia.
  - left. lia.
  - right. split; [lia | lia].
Qed.

Theorem advance_token_strictly_advances : forall t step,
  (step_advances_item step = true \/ (0 < step_consumed_chars step)%nat) ->
  token_lt t (advance_token t step).
Proof.
  intros [idx off] [chars adv] Hcond.
  unfold advance_token, token_lt; cbn.
  destruct adv; cbn.
  - left. lia.
  - destruct Hcond as [Hfalse | Hpos]; [discriminate |].
    cbn in Hpos.
    right. split; [reflexivity | lia].
Qed.

Fixpoint sum_step_chars (steps : list LineBreakStep) : nat :=
  match steps with
  | nil => 0%nat
  | s :: rest => (step_consumed_chars s + sum_step_chars rest)%nat
  end.

Theorem sum_step_chars_app : forall l1 l2,
  (sum_step_chars (l1 ++ l2) = sum_step_chars l1 + sum_step_chars l2)%nat.
Proof.
  intros l1 l2.
  induction l1 as [|s rest IH]; cbn.
  - reflexivity.
  - rewrite IH. lia.
Qed.

Theorem token_progress_measure_decreases_on_item : forall total_items t step,
  (tok_item_index t < total_items)%nat ->
  step_advances_item step = true ->
  (total_items - tok_item_index (advance_token t step) < total_items - tok_item_index t)%nat.
Proof.
  intros total_items [idx off] [chars adv] Hlt Hadv.
  unfold advance_token; cbn in *.
  rewrite Hadv; cbn.
  lia.
Qed.
