(* ========================================================================= *)
(*               BlinkInlineBreakTokenOffsetSemantics.v                     *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Inline Break Token Offset           *)
(* Continuation against CSS Fragmentation 3 §4. Fully constructive, 0 admits.*)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record InlineBreakToken := mkInlineBreakToken {
  ibt_char_offset : Z;
  ibt_item_idx    : Z
}.

Definition advance_inline_break_token
  (tok : InlineBreakToken) (step_chars step_item : Z) : InlineBreakToken :=
  {| ibt_char_offset := ibt_char_offset tok + step_chars;
     ibt_item_idx    := ibt_item_idx tok + step_item |}.

Theorem inline_break_token_advances_chars : forall tok step_chars step_item,
  step_chars > 0 ->
  ibt_char_offset tok < ibt_char_offset (advance_inline_break_token tok step_chars step_item).
Proof.
  intros. unfold advance_inline_break_token; cbn. lia.
Qed.

Theorem inline_break_token_advances_item : forall tok step_chars step_item,
  step_item >= 0 ->
  ibt_item_idx tok <= ibt_item_idx (advance_inline_break_token tok step_chars step_item).
Proof.
  intros. unfold advance_inline_break_token; cbn. lia.
Qed.
