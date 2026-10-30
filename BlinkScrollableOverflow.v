(******************************************************************************)
(* BlinkScrollableOverflow.v                                                  *)
(* Sound Formal Big-Step Operational Semantics for CSS Scrollable Overflow    *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Overflow Module Level 3 (§3 Scrollable Overflow)                *)
(* 2. Blink PaintLayerScrollableArea & ScrollableOverflowCalculator           *)
(*    (`third_party/blink/renderer/core/paint/paint_layer_scrollable_area.cc`)*)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkPhysicalFragment.
Require Import BlinkShadowAndOverflow.
Import ListNotations.
Open Scope Z_scope.

Record ScrollBounds := mkScrollBounds {
  sb_min_x : Z;
  sb_min_y : Z;
  sb_max_x : Z;
  sb_max_y : Z
}.

Definition default_scroll_bounds (w h : Z) : ScrollBounds :=
  mkScrollBounds 0 0 (sat_clamp w) (sat_clamp h).

Definition union_scroll_rect (sb : ScrollBounds) (rx ry rw rh : Z) : ScrollBounds :=
  mkScrollBounds
    (Z.min (sb_min_x sb) rx)
    (Z.min (sb_min_y sb) ry)
    (Z.max (sb_max_x sb) (sat_clamp (rx + rw)))
    (Z.max (sb_max_y sb) (sat_clamp (ry + rh))).

(** In LTR horizontal-tb, scroll origin is (0, 0), and scrollable overflow
    cannot extend into negative coordinates *)
Definition clamp_scrollable_overflow_ltr (sb : ScrollBounds) (border_w border_h : Z) : ScrollBounds :=
  mkScrollBounds
    0
    0
    (Z.max border_w (sb_max_x sb))
    (Z.max border_h (sb_max_y sb)).

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem clamp_scrollable_overflow_contains_border_box :
  forall sb bw bh,
    0 <= bw -> 0 <= bh ->
    let clamped := clamp_scrollable_overflow_ltr sb bw bh in
    sb_min_x clamped = 0 /\
    sb_min_y clamped = 0 /\
    bw <= sb_max_x clamped /\
    bh <= sb_max_y clamped.
Proof.
  intros sb bw bh Hbw Hbh.
  unfold clamp_scrollable_overflow_ltr. simpl.
  repeat split; try lia; apply Z.le_max_l.
Qed.

Theorem union_scroll_rect_monotonic :
  forall sb rx ry rw rh,
    0 <= rw -> 0 <= rh ->
    let updated := union_scroll_rect sb rx ry rw rh in
    sb_min_x updated <= sb_min_x sb /\
    sb_min_y updated <= sb_min_y sb /\
    sb_max_x sb <= sb_max_x updated /\
    sb_max_y sb <= sb_max_y updated.
Proof.
  intros sb rx ry rw rh Hrw Hrh.
  unfold union_scroll_rect. simpl.
  repeat split; [apply Z.le_min_l | apply Z.le_min_l | apply Z.le_max_l | apply Z.le_max_l].
Qed.
