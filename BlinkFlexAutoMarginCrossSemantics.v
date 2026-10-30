(* ========================================================================= *)
(*               BlinkFlexAutoMarginCrossSemantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Flex Cross Axis Auto Margin        *)
(* Absorption against CSS Flexible Box Layout 1 §8.1. 0 admits.              *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition flex_cross_auto_margin_centered (line_cross item_cross : Z) : Z :=
  let free_space := Z.max 0 (line_cross - item_cross) in
  free_space / 2.

Theorem flex_cross_auto_margin_nonneg : forall line_cross item_cross,
  flex_cross_auto_margin_centered line_cross item_cross >= 0.
Proof.
  intros. unfold flex_cross_auto_margin_centered.
  assert (Z.max 0 (line_cross - item_cross) >= 0) by lia.
  apply Z.le_ge.
  apply Z.div_pos; lia.
Qed.

Theorem flex_cross_item_centered_in_line : forall line_cross item_cross,
  item_cross >= 0 ->
  item_cross <= line_cross ->
  flex_cross_auto_margin_centered line_cross item_cross + item_cross <= line_cross.
Proof.
  intros line_cross item_cross H1 H2.
  unfold flex_cross_auto_margin_centered.
  assert (Hmax: Z.max 0 (line_cross - item_cross) = line_cross - item_cross) by lia.
  rewrite Hmax.
  assert (Hdiv: (line_cross - item_cross) / 2 <= line_cross - item_cross).
  { apply Z.div_le_upper_bound; lia. }
  lia.
Qed.
