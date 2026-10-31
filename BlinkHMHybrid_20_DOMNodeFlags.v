(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record DOMNodeFlags := mkDOMNodeFlags {
  domnodeflags_element_index : Z;
  domnodeflags_sibling_count : Z;
  domnodeflags_is_connected : bool
}.

Definition nth_child_position (a_step : Z) (b_offset : Z) (k_iter : Z) : Z :=
  a_step * k_iter + b_offset.

Theorem nth_child_position_positive :
  forall (a_step b_offset k_iter : Z), 0 <= a_step -> 1 <= b_offset -> 0 <= k_iter -> 1 <= nth_child_position a_step b_offset k_iter.
Proof.
  intros a_step b_offset k_iter Ha Hb Hk.
  unfold nth_child_position.
  assert (Hmul : 0 <= a_step * k_iter) by (apply Z.mul_nonneg_nonneg; lia).
  lia.
Qed.
