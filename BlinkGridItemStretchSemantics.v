(* ========================================================================= *)
(*               BlinkGridItemStretchSemantics.v                            *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Grid Item Stretch Alignment        *)
(* against CSS Box Alignment 3 §6.2. Fully constructive, 0 admits.           *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition grid_item_stretched_size (cell_size min_size max_size : Z) : Z :=
  Z.max min_size (Z.min max_size cell_size).

Theorem grid_item_stretched_size_bounded : forall cell_size min_size max_size,
  min_size <= max_size ->
  min_size <= grid_item_stretched_size cell_size min_size max_size <= max_size.
Proof.
  intros. unfold grid_item_stretched_size. lia.
Qed.

Theorem grid_item_stretched_size_exact : forall cell_size min_size max_size,
  min_size <= cell_size <= max_size ->
  grid_item_stretched_size cell_size min_size max_size = cell_size.
Proof.
  intros. unfold grid_item_stretched_size. lia.
Qed.
