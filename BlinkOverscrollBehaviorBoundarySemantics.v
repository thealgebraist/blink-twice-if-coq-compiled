Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Overscroll Behavior Containment Semantics *)
(** CSS Overscroll Behavior 1 §3: scroll chaining prevention *)

Inductive OverscrollBehavior :=
  | OverscrollAuto
  | OverscrollContain
  | OverscrollNone.

Definition can_chain_scroll_to_parent (b : OverscrollBehavior) : bool :=
  match b with
  | OverscrollAuto => true
  | OverscrollContain => false
  | OverscrollNone => false
  end.

Theorem contain_prevents_chaining :
  can_chain_scroll_to_parent OverscrollContain = false.
Proof.
  reflexivity.
Qed.

Theorem auto_permits_chaining :
  can_chain_scroll_to_parent OverscrollAuto = true.
Proof.
  reflexivity.
Qed.
