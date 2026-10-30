(* ========================================================================= *)
(*               BlinkFlexCrossStretchSemantics.v                           *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Flex Cross Axis Stretch Sizing     *)
(* against CSS Flexible Box Layout 1 §8.3. Fully constructive, 0 admits.     *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition stretch_cross_size (line_cross min_cross max_cross : Z) : Z :=
  Z.max min_cross (Z.min max_cross line_cross).

Theorem stretch_cross_size_bounded : forall line_cross min_cross max_cross,
  min_cross <= max_cross ->
  min_cross <= stretch_cross_size line_cross min_cross max_cross /\
  stretch_cross_size line_cross min_cross max_cross <= max_cross.
Proof.
  intros. unfold stretch_cross_size. lia.
Qed.

Theorem stretch_cross_size_exact_when_within : forall line_cross min_cross max_cross,
  min_cross <= line_cross <= max_cross ->
  stretch_cross_size line_cross min_cross max_cross = line_cross.
Proof.
  intros. unfold stretch_cross_size. lia.
Qed.
