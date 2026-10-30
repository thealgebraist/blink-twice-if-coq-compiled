(**
  BlinkStickyPositionSemantics.v
  Formal specification of Chromium Blink sticky positioning constraints and scroll range clamping
  derived from third_party/blink/renderer/core/layout/sticky_position_scroller_data.cc
  and layout_box_model_object.cc
  according to W3C CSS Positioned Layout Module Level 3 (§6 Sticky Positioning).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Sticky 1D Constraint Computation *)

Record Sticky1DConstraints := {
  static_position : Z;
  sticky_inset : Z;
  cb_max_shift : Z
}.

Definition compute_desired_shift (c : Sticky1DConstraints) (scroll_offset : Z) : Z :=
  (scroll_offset + c.(sticky_inset)) - c.(static_position).

Definition compute_sticky_offset (c : Sticky1DConstraints) (scroll_offset : Z) : Z :=
  let desired := compute_desired_shift c scroll_offset in
  Z.max 0 (Z.min desired c.(cb_max_shift)).

(** 2. Invariant Theorems *)

Theorem sticky_offset_nonneg :
  forall (c : Sticky1DConstraints) (scroll_offset : Z),
    0 <= compute_sticky_offset c scroll_offset.
Proof.
  intros c scroll_offset.
  unfold compute_sticky_offset.
  apply Z.le_max_l.
Qed.

Theorem sticky_offset_bounded_by_cb_limit :
  forall (c : Sticky1DConstraints) (scroll_offset : Z),
    0 <= c.(cb_max_shift) ->
    compute_sticky_offset c scroll_offset <= c.(cb_max_shift).
Proof.
  intros c scroll_offset Hcb.
  unfold compute_sticky_offset.
  apply Z.max_lub.
  - exact Hcb.
  - apply Z.le_min_r.
Qed.

Theorem sticky_offset_inactive_before_trigger :
  forall (c : Sticky1DConstraints) (scroll_offset : Z),
    scroll_offset + c.(sticky_inset) <= c.(static_position) ->
    compute_sticky_offset c scroll_offset = 0.
Proof.
  intros c scroll_offset Hbefore.
  unfold compute_sticky_offset, compute_desired_shift.
  assert (Hdesired : (scroll_offset + c.(sticky_inset)) - c.(static_position) <= 0) by lia.
  assert (Z.min ((scroll_offset + c.(sticky_inset)) - c.(static_position)) c.(cb_max_shift) <= 0).
  {
    pose proof (Z.le_min_l ((scroll_offset + c.(sticky_inset)) - c.(static_position)) c.(cb_max_shift)).
    lia.
  }
  apply Z.max_l; lia.
Qed.

Theorem sticky_offset_clamped_at_cb_limit :
  forall (c : Sticky1DConstraints) (scroll_offset : Z),
    0 <= c.(cb_max_shift) ->
    c.(cb_max_shift) <= compute_desired_shift c scroll_offset ->
    compute_sticky_offset c scroll_offset = c.(cb_max_shift).
Proof.
  intros c scroll_offset Hcb Hpast.
  unfold compute_sticky_offset.
  assert (Z.min (compute_desired_shift c scroll_offset) c.(cb_max_shift) = c.(cb_max_shift)).
  { apply Z.min_r. exact Hpast. }
  rewrite H.
  apply Z.max_r.
  exact Hcb.
Qed.

Theorem sticky_offset_monotonic_in_range :
  forall (c : Sticky1DConstraints) (s1 s2 : Z),
    0 <= c.(cb_max_shift) ->
    s1 <= s2 ->
    compute_sticky_offset c s1 <= compute_sticky_offset c s2.
Proof.
  intros c s1 s2 Hcb Hs.
  unfold compute_sticky_offset, compute_desired_shift.
  lia.
Qed.
