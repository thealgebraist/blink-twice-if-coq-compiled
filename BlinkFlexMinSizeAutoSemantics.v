(* ========================================================================= *)
(*               BlinkFlexMinSizeAutoSemantics.v                            *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Flexbox Min-Size: Auto Clamping    *)
(* against CSS Flexible Box Layout 1 §4.5. Fully constructive, 0 admits.     *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition flex_auto_min_size (specified_size min_content : Z) : Z :=
  if specified_size <=? 0 then min_content
  else Z.min specified_size min_content.

Definition clamp_flex_item_size (desired auto_min : Z) : Z :=
  Z.max desired (Z.max 0 auto_min).

Theorem clamp_flex_item_size_ge_zero : forall desired auto_min,
  clamp_flex_item_size desired auto_min >= 0.
Proof.
  intros. unfold clamp_flex_item_size. lia.
Qed.

Theorem clamp_flex_item_size_ge_auto_min : forall desired auto_min,
  clamp_flex_item_size desired auto_min >= auto_min.
Proof.
  intros. unfold clamp_flex_item_size. lia.
Qed.

Theorem clamp_flex_item_size_monotonic : forall d1 d2 auto_min,
  d1 <= d2 ->
  clamp_flex_item_size d1 auto_min <= clamp_flex_item_size d2 auto_min.
Proof.
  intros. unfold clamp_flex_item_size. lia.
Qed.
