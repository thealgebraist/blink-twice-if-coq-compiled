(**
  BlinkBreakTokenAppealSemantics.v
  Formal specification of Chromium Blink fragmentation break tokens and break appeal
  derived from third_party/blink/renderer/core/layout/fragmentation/break_token.cc
  and break_appeal.cc
  according to W3C CSS Fragmentation Module Level 3 (§4 Fragmenting Elements: Break Tokens & Break Appeal).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Break Appeal Total Order *)

Inductive BreakAppeal : Type :=
  | kBreakAppealLastResort
  | kBreakAppealViolatesOrphanWidow
  | kBreakAppealNone
  | kBreakAppealPerfect.

Definition appeal_rank (a : BreakAppeal) : Z :=
  match a with
  | kBreakAppealLastResort          => 0
  | kBreakAppealViolatesOrphanWidow => 1
  | kBreakAppealNone                => 2
  | kBreakAppealPerfect             => 3
  end.

Definition appeal_lt (a1 a2 : BreakAppeal) : Prop :=
  appeal_rank a1 < appeal_rank a2.

Definition appeal_le (a1 a2 : BreakAppeal) : Prop :=
  appeal_rank a1 <= appeal_rank a2.

Theorem appeal_order_transitive :
  forall a1 a2 a3 : BreakAppeal,
    appeal_lt a1 a2 -> appeal_lt a2 a3 -> appeal_lt a1 a3.
Proof.
  unfold appeal_lt.
  intros a1 a2 a3 H12 H23.
  lia.
Qed.

Theorem appeal_order_antisymmetric :
  forall a1 a2 : BreakAppeal,
    appeal_le a1 a2 -> appeal_le a2 a1 -> a1 = a2.
Proof.
  unfold appeal_le.
  intros a1 a2 H12 H21.
  assert (appeal_rank a1 = appeal_rank a2) by lia.
  destruct a1; destruct a2; simpl in H; try reflexivity; try discriminate.
Qed.

Theorem perfect_strictly_better_than_orphan_violation :
  appeal_lt kBreakAppealViolatesOrphanWidow kBreakAppealPerfect.
Proof.
  unfold appeal_lt.
  simpl. lia.
Qed.

(** 2. Break Token State and Consumption Accumulation *)

Record BlockBreakToken := {
  sequence_number : Z;
  consumed_block_size : Z;
  is_at_block_end : bool
}.

Definition resume_and_consume
    (token : option BlockBreakToken) (fragment_block_size : Z) (total_block_size : Z) : BlockBreakToken :=
  let prev_consumed := match token with Some t => t.(consumed_block_size) | None => 0 end in
  let prev_seq := match token with Some t => t.(sequence_number) | None => -1 end in
  let new_consumed := prev_consumed + fragment_block_size in
  {|
    sequence_number := prev_seq + 1;
    consumed_block_size := new_consumed;
    is_at_block_end := total_block_size <=? new_consumed
  |}.

Theorem sequence_number_strictly_advances :
  forall (token : BlockBreakToken) (h total_h : Z),
    (resume_and_consume (Some token) h total_h).(sequence_number) = token.(sequence_number) + 1.
Proof.
  intros token h total_h.
  unfold resume_and_consume.
  simpl. lia.
Qed.

Theorem consumed_block_size_monotonic :
  forall (token : BlockBreakToken) (h total_h : Z),
    0 <= h ->
    token.(consumed_block_size) <= (resume_and_consume (Some token) h total_h).(consumed_block_size).
Proof.
  intros token h total_h Hh.
  unfold resume_and_consume.
  simpl. lia.
Qed.

Theorem multiple_fragments_accumulate_sum :
  forall (h1 h2 total_h : Z),
    let t1 := resume_and_consume None h1 total_h in
    let t2 := resume_and_consume (Some t1) h2 total_h in
    t2.(consumed_block_size) = h1 + h2.
Proof.
  intros h1 h2 total_h t1 t2.
  unfold t2, t1, resume_and_consume.
  simpl. lia.
Qed.

