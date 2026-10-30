(**
  BlinkInlineBoxTreeSemantics.v
  Formal specification of Chromium Blink inline box tree assembly and atomic inline segmentation
  derived from third_party/blink/renderer/core/layout/inline/inline_box_state.cc and line_info.cc
  according to W3C CSS Inline Layout Module Level 3 (§3 Inline Box Formatting Context Tree Generation).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Inductive InlineItemKind : Type :=
  | ItemOpenTag (tag_id : Z) (start_mbp : Z)
  | ItemCloseTag (tag_id : Z) (end_mbp : Z)
  | ItemText (text_width : Z)
  | ItemAtomicInline (atomic_width : Z).

Record InlineStackFrame := {
  frame_tag_id : Z;
  frame_start_mbp : Z
}.

Definition InlineStack := list InlineStackFrame.

Record LineBoxState := {
  state_stack : InlineStack;
  consumed_inline_size : Z
}.

Definition process_inline_item (st : LineBoxState) (it : InlineItemKind) : LineBoxState :=
  match it with
  | ItemOpenTag tid smbp =>
      {|
        state_stack := {| frame_tag_id := tid; frame_start_mbp := smbp |} :: st.(state_stack);
        consumed_inline_size := st.(consumed_inline_size) + smbp
      |}
  | ItemCloseTag tid embp =>
      match st.(state_stack) with
      | [] => st
      | top :: rest =>
          {|
            state_stack := rest;
            consumed_inline_size := st.(consumed_inline_size) + embp
          |}
      end
  | ItemText w =>
      {|
        state_stack := st.(state_stack);
        consumed_inline_size := st.(consumed_inline_size) + w
      |}
  | ItemAtomicInline w =>
      {|
        state_stack := st.(state_stack);
        consumed_inline_size := st.(consumed_inline_size) + w
      |}
  end.

(** 1. Stack Push / Pop Balance Invariants *)

Theorem open_tag_increases_stack_depth :
  forall (st : LineBoxState) (tid smbp : Z),
    length (process_inline_item st (ItemOpenTag tid smbp)).(state_stack) =
    (length st.(state_stack) + 1)%nat.
Proof.
  intros st tid smbp.
  simpl. lia.
Qed.

Theorem close_tag_decreases_nonempty_stack :
  forall (st : LineBoxState) (top : InlineStackFrame) (rest : InlineStack) (tid embp : Z),
    st.(state_stack) = top :: rest ->
    length (process_inline_item st (ItemCloseTag tid embp)).(state_stack) =
    (length st.(state_stack) - 1)%nat.
Proof.
  intros st top rest tid embp Hst.
  unfold process_inline_item.
  rewrite Hst.
  simpl. lia.
Qed.

Theorem balanced_tag_pair_restores_stack :
  forall (st : LineBoxState) (tid smbp embp : Z),
    (process_inline_item
       (process_inline_item st (ItemOpenTag tid smbp))
       (ItemCloseTag tid embp)).(state_stack) = st.(state_stack).
Proof.
  intros st tid smbp embp.
  simpl. reflexivity.
Qed.

(** 2. Consumed Size Monotonicity *)

Theorem inline_advance_monotonic :
  forall (st : LineBoxState) (it : InlineItemKind),
    (match it with
     | ItemOpenTag _ smbp => 0 <= smbp
     | ItemCloseTag _ embp => 0 <= embp
     | ItemText w => 0 <= w
     | ItemAtomicInline w => 0 <= w
     end) ->
    st.(consumed_inline_size) <= (process_inline_item st it).(consumed_inline_size).
Proof.
  intros st it Hpos.
  destruct it; simpl in *; try lia.
  destruct (state_stack st); simpl; lia.
Qed.
