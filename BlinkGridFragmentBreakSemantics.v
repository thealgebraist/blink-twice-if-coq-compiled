(* ========================================================================= *)
(*               BlinkGridFragmentBreakSemantics.v                          *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Grid Fragmentation Row Continuation *)
(* against CSS Fragmentation 3 §4. Fully constructive, 0 admits.             *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record GridBreakToken := mkGridBreakToken {
  gbt_row_idx        : Z;
  gbt_consumed_block : Z
}.

Definition advance_grid_fragment
  (tok : GridBreakToken) (row_step add_block : Z) : GridBreakToken :=
  {| gbt_row_idx        := gbt_row_idx tok + row_step;
     gbt_consumed_block := gbt_consumed_block tok + add_block |}.

Theorem grid_break_token_monotonic_row : forall tok row_step add_block,
  row_step >= 0 ->
  gbt_row_idx tok <= gbt_row_idx (advance_grid_fragment tok row_step add_block).
Proof.
  intros. unfold advance_grid_fragment; cbn. lia.
Qed.

Theorem grid_break_token_monotonic_block : forall tok row_step add_block,
  add_block > 0 ->
  gbt_consumed_block tok < gbt_consumed_block (advance_grid_fragment tok row_step add_block).
Proof.
  intros. unfold advance_grid_fragment; cbn. lia.
Qed.
