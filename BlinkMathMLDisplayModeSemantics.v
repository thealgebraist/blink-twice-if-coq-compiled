Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Display Mode Semantics *)
(** MathML Core §2.1: math display block vs inline display modes *)

Inductive MathMLDisplayMode :=
  | MathMLDisplayInline
  | MathMLDisplayBlock.

Definition is_block_math (m : MathMLDisplayMode) : bool :=
  match m with
  | MathMLDisplayBlock => true
  | MathMLDisplayInline => false
  end.

Theorem block_display_is_block :
  is_block_math MathMLDisplayBlock = true.
Proof.
  reflexivity.
Qed.

Theorem inline_display_is_not_block :
  is_block_math MathMLDisplayInline = false.
Proof.
  reflexivity.
Qed.
