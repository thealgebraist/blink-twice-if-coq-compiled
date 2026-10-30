Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Page Break Opportunity Classification Semantics *)
(** CSS Fragmentation 3 §3.1: break opportunity classes *)

Inductive BreakOpportunityClass :=
  | BreakClassA   (* Between sibling box fragments *)
  | BreakClassB   (* Between line boxes *)
  | BreakClassC.  (* Inside box fragment *)

Definition is_valid_break_opportunity (c : BreakOpportunityClass) : bool :=
  match c with
  | BreakClassA => true
  | BreakClassB => true
  | BreakClassC => false
  end.

Theorem class_a_permits_break :
  is_valid_break_opportunity BreakClassA = true.
Proof.
  reflexivity.
Qed.

Theorem class_b_permits_break :
  is_valid_break_opportunity BreakClassB = true.
Proof.
  reflexivity.
Qed.
