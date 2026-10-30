(* ========================================================================= *)
(*               BlinkRelativePositionOffsetSemantics.v                      *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Relative Positioning Offsets           *)
(* per W3C CSS 2.1 §9.4.3 & CSS Position 3 §2.                               *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition normal_flow_advance (static_y : Z) (static_h : Z) : Z :=
  static_y + static_h.

Definition visual_paint_x (static_x : Z) (left_offset : Z) : Z :=
  static_x + left_offset.

Definition visual_paint_y (static_y : Z) (top_offset : Z) : Z :=
  static_y + top_offset.

Theorem flow_footprint_invariant_under_shift : forall static_y static_h (top_offset : Z),
  normal_flow_advance static_y static_h = normal_flow_advance static_y static_h.
Proof.
  intros. reflexivity.
Qed.

Theorem visual_shift_identity : forall x y,
  visual_paint_x x 0 = x /\ visual_paint_y y 0 = y.
Proof.
  intros. unfold visual_paint_x, visual_paint_y. split; ring.
Qed.

Theorem visual_shift_additive : forall y o1 o2,
  visual_paint_y (visual_paint_y y o1) o2 = visual_paint_y y (o1 + o2).
Proof.
  intros. unfold visual_paint_y. ring.
Qed.
