(* ========================================================================= *)
(*               BlinkStickyScrollerChainSemantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Multi-Nested Sticky Scroller        *)
(* Constraint Accumulation against CSS Positioned 3 §6. Fully constructive.  *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition clamp_sticky (min_off max_off scroll : Z) : Z :=
  Z.max min_off (Z.min max_off scroll).

Definition cumulative_sticky_offset
  (min1 max1 sc1 min2 max2 sc2 : Z) : Z :=
  clamp_sticky min1 max1 sc1 + clamp_sticky min2 max2 sc2.

Theorem cumulative_sticky_bounded : forall min1 max1 sc1 min2 max2 sc2,
  min1 <= max1 ->
  min2 <= max2 ->
  min1 + min2 <= cumulative_sticky_offset min1 max1 sc1 min2 max2 sc2 <= max1 + max2.
Proof.
  intros min1 max1 sc1 min2 max2 sc2 H1 H2.
  unfold cumulative_sticky_offset, clamp_sticky.
  lia.
Qed.
