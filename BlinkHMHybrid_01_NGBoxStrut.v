(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record NGBoxStrut := mkNGBoxStrut {
  ngboxstrut_inline_start : Z;
  ngboxstrut_inline_end : Z;
  ngboxstrut_block_start : Z;
  ngboxstrut_block_end : Z
}.

Definition inline_sum (in_start : Z) (in_end : Z) : Z :=
  in_start + in_end.

Theorem inline_sum_nonneg :
  forall (in_start in_end : Z), 0 <= in_start -> 0 <= in_end -> 0 <= inline_sum in_start in_end.
Proof.
  intros in_start in_end His Hie. unfold inline_sum. lia.
Qed.
