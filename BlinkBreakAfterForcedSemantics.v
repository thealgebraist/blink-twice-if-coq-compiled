Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Forced Break After Page Semantics *)
(** CSS Fragmentation 3 §3.2: forced break after state *)

Inductive BreakAfterType :=
  | BreakAfterAuto
  | BreakAfterPage
  | BreakAfterColumn.

Definition is_forced_page_break_after (t : BreakAfterType) : bool :=
  match t with
  | BreakAfterPage => true
  | _ => false
  end.

Theorem page_break_after_is_forced :
  is_forced_page_break_after BreakAfterPage = true.
Proof.
  reflexivity.
Qed.

Theorem auto_break_after_is_not_forced :
  is_forced_page_break_after BreakAfterAuto = false.
Proof.
  reflexivity.
Qed.
