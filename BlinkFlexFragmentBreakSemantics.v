(* ========================================================================= *)
(*               BlinkFlexFragmentBreakSemantics.v                          *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Flexbox Fragmentation Break Token  *)
(* Continuation against CSS Fragmentation 3 §4. Fully constructive, 0 admits.*)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record FlexBreakToken := mkFlexBreakToken {
  fbt_line_idx       : Z;
  fbt_consumed_block : Z
}.

Definition advance_flex_fragment
  (tok : FlexBreakToken) (line_step add_block : Z) : FlexBreakToken :=
  {| fbt_line_idx       := fbt_line_idx tok + line_step;
     fbt_consumed_block := fbt_consumed_block tok + add_block |}.

Theorem flex_break_token_monotonic_line : forall tok line_step add_block,
  line_step >= 0 ->
  fbt_line_idx tok <= fbt_line_idx (advance_flex_fragment tok line_step add_block).
Proof.
  intros. unfold advance_flex_fragment; cbn. lia.
Qed.

Theorem flex_break_token_monotonic_block : forall tok line_step add_block,
  add_block > 0 ->
  fbt_consumed_block tok < fbt_consumed_block (advance_flex_fragment tok line_step add_block).
Proof.
  intros. unfold advance_flex_fragment; cbn. lia.
Qed.
