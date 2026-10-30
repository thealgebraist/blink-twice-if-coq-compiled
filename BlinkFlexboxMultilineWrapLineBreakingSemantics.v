Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Flexbox Multiline Wrap Line Breaking Semantics *)
(** CSS Flexbox 1 §9.3: multiline flex line breaking *)

Definition should_break_flex_line (curr_main item_main avail_main item_count : Z) : bool :=
  (0 <? item_count) && (avail_main <? curr_main + item_main).

Theorem break_requires_non_empty_and_overflow : forall curr item avail count,
  should_break_flex_line curr item avail count = true ->
  count > 0 /\ curr + item > avail.
Proof.
  intros curr item avail count H.
  unfold should_break_flex_line in H.
  apply andb_prop in H.
  destruct H as [Hcnt Hovf].
  apply Z.ltb_lt in Hcnt.
  apply Z.ltb_lt in Hovf.
  split; lia.
Qed.
