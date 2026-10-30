From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §8.3.1 BFC Root Margin Non-Collapsing Boundary *)
Record BFCContainer := {
  bfc_border_padding_top : Z;
  bfc_child_margin_top : Z;
  bfc_child_height : Z;
  bfc_border_padding_bottom : Z
}.

Definition bfc_total_block_size (c : BFCContainer) : Z :=
  bfc_border_padding_top c + bfc_child_margin_top c + bfc_child_height c + bfc_border_padding_bottom c.

Theorem bfc_contains_child_margin : forall c,
  bfc_border_padding_top c >= 0 ->
  bfc_child_margin_top c >= 0 ->
  bfc_child_height c >= 0 ->
  bfc_border_padding_bottom c >= 0 ->
  bfc_total_block_size c >= bfc_child_margin_top c.
Proof.
  intros [bp_t cm_t ch bp_b] H1 H2 H3 H4.
  cbn in *. unfold bfc_total_block_size; cbn.
  lia.
Qed.
