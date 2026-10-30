Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Accessible Name Fallback Precedence Semantics *)
(** Accessible Name and Description §2: aria-labelledby takes highest priority *)

Definition resolve_accessible_name (has_labelledby has_label has_title : bool) : Z :=
  if has_labelledby then 1
  else if has_label then 2
  else if has_title then 3
  else 4.

Theorem labelledby_takes_highest_precedence : forall l t,
  resolve_accessible_name true l t = 1.
Proof.
  intros l t; reflexivity.
Qed.

Theorem aria_label_precedes_title : forall t,
  resolve_accessible_name false true t = 2.
Proof.
  intros t; reflexivity.
Qed.
