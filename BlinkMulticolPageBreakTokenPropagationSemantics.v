Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Multicol Page Break Token Propagation Semantics *)
(** CSS Fragmentation 3 §5.1: token chaining across pages *)

Record PageBreakToken := {
  token_page_index : Z;
  token_consumed_block : Z
}.

Definition propagate_page_break_token (tok : PageBreakToken) (consumed_on_page : Z) : PageBreakToken :=
  {| token_page_index := token_page_index tok + 1;
     token_consumed_block := token_consumed_block tok + Z.max 0 consumed_on_page |}.

Theorem propagation_advances_page_index : forall tok consumed,
  token_page_index tok < token_page_index (propagate_page_break_token tok consumed).
Proof.
  intros tok consumed.
  unfold propagate_page_break_token; simpl.
  lia.
Qed.

Theorem propagation_monotonically_accumulates : forall tok consumed,
  token_consumed_block tok <= token_consumed_block (propagate_page_break_token tok consumed).
Proof.
  intros tok consumed.
  unfold propagate_page_break_token; simpl.
  lia.
Qed.
