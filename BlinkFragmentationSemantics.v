(******************************************************************************)
(* BlinkFragmentationSemantics.v                                              *)
(* Sound Formal Big-Step Operational Semantics for CSS Multicol & Pagination  *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Fragmentation Module Level 3 (§3 Fragmentainers, §4 Breaks)    *)
(* 2. Blink LayoutNG Fragmentation (`ng_fragmentation_utils.cc`) &            *)
(*    BlockBreakToken (`block_break_token.h`)                                 *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkPhysicalFragment.
Import ListNotations.
Open Scope Z_scope.

Inductive BreakStatus : Type :=
  | BreakNone
  | BreakContinue (consumed_delta : Z)
  | BreakFinished.

Record BreakToken := mkBreakToken {
  bt_consumed_block_size : Z;
  bt_is_at_block_end : bool
}.

Definition default_break_token : BreakToken := mkBreakToken 0 false.

Record Fragmentainer := mkFragmentainer {
  fg_index : Z;
  fg_size : Z;
  fg_offset : Z
}.

(** Formally models fragmentation of a block box across finite fragmentainers *)
Definition step_fragmentainer_slice (total_height : Z) (token : BreakToken)
                                   (fg : Fragmentainer) : (Z * BreakToken * BreakStatus) :=
  let already_consumed := bt_consumed_block_size token in
  let remaining_content := sat_clamp (total_height - already_consumed) in
  if remaining_content <=? 0 then
    (0, mkBreakToken already_consumed true, BreakFinished)
  else
    let avail := fg_size fg in
    if remaining_content <=? avail then
      (* Entire remaining content fits in current fragmentainer *)
      (remaining_content, mkBreakToken total_height true, BreakFinished)
    else
      (* Slices content at fragmentainer boundary *)
      let slice := avail in
      (slice, mkBreakToken (already_consumed + slice) false, BreakContinue slice).

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem fragmentation_slice_progress :
  forall tot tok fg slice next_tok status,
    0 < fg_size fg ->
    bt_consumed_block_size tok < tot ->
    step_fragmentainer_slice tot tok fg = (slice, next_tok, status) ->
    0 < slice /\ bt_consumed_block_size tok < bt_consumed_block_size next_tok.
Proof.
  intros tot tok fg slice next_tok status Hfg_pos Htok_lt Hstep.
  unfold step_fragmentainer_slice in Hstep.
  remember (sat_clamp (tot - bt_consumed_block_size tok)) as rem.
  assert (Hrem_pos : 0 < rem).
  { subst rem. unfold sat_clamp.
    destruct (Z.gtb_spec (tot - bt_consumed_block_size tok) kInt32Max); [unfold kInt32Max; lia |].
    destruct (Z.ltb_spec (tot - bt_consumed_block_size tok) kInt32Min); [unfold kInt32Min in *; lia | lia]. }
  destruct (rem <=? 0) eqn:Erem.
  - apply Z.leb_le in Erem. lia.
  - destruct (rem <=? fg_size fg) eqn:Efit.
    + inversion Hstep; subst. simpl. split; [lia | lia].
    + inversion Hstep; subst. simpl. split; [lia | lia].
Qed.

Theorem fragmentation_slice_deterministic :
  forall tot tok fg r1 r2,
    step_fragmentainer_slice tot tok fg = r1 ->
    step_fragmentainer_slice tot tok fg = r2 ->
    r1 = r2.
Proof.
  intros tot tok fg r1 r2 H1 H2.
  subst. reflexivity.
Qed.
