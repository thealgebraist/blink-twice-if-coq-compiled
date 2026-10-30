Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Checkbox Indeterminate Tri-State Semantics *)
(** HTML Standard §4.10.5.1: checkbox tri-state check *)

Inductive CheckboxState :=
  | CheckboxUnchecked
  | CheckboxChecked
  | CheckboxIndeterminate.

Definition is_checked_state (s : CheckboxState) : bool :=
  match s with
  | CheckboxChecked => true
  | _ => false
  end.

Theorem indeterminate_is_not_checked :
  is_checked_state CheckboxIndeterminate = false.
Proof.
  reflexivity.
Qed.

Theorem checked_is_checked :
  is_checked_state CheckboxChecked = true.
Proof.
  reflexivity.
Qed.
