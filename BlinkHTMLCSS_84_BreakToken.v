(* Blink2Coq HTML/CSS Synthesis for BreakToken *)
(* Source: renderer/core/layout/break_token.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition next_consumed_block_size (consumed chunk : Z) : Z := consumed + chunk.
Theorem break_progress_strictly_monotonic : forall consumed chunk,
  0 < chunk -> consumed < next_consumed_block_size consumed chunk.
Proof. intros. unfold next_consumed_block_size. lia. Qed.
