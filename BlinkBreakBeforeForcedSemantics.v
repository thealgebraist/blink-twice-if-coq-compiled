Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Forced Break Before Page Semantics *)
(** CSS Fragmentation 3 §3.2: forced break before state *)

Inductive BreakBeforeType :=
  | BreakBeforeAuto
  | BreakBeforePage
  | BreakBeforeColumn.

Definition is_forced_page_break_before (t : BreakBeforeType) : bool :=
  match t with
  | BreakBeforePage => true
  | _ => false
  end.

Theorem page_break_before_is_forced :
  is_forced_page_break_before BreakBeforePage = true.
Proof.
  reflexivity.
Qed.

Theorem auto_break_before_is_not_forced :
  is_forced_page_break_before BreakBeforeAuto = false.
Proof.
  reflexivity.
Qed.
