(**
  BlinkStickyMultiAxisSemantics.v
  Formal specification of Chromium Blink 2D multi-axis sticky positioning
  derived from third_party/blink/renderer/core/layout/sticky_position_scroller_data.cc
  and logical_rect.h
  according to W3C CSS Positioned Layout Module Level 3 (§6.3 Multi-axis Sticky Positioning).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record PhysicalRect := {
  rect_x : Z;
  rect_y : Z;
  rect_w : Z;
  rect_h : Z
}.

Definition rect_right (r : PhysicalRect) : Z :=
  r.(rect_x) + r.(rect_w).

Definition rect_bottom (r : PhysicalRect) : Z :=
  r.(rect_y) + r.(rect_h).

Record StickyAxisConstraint := {
  desired_shift : Z;
  cb_min_shift : Z;
  cb_max_shift : Z
}.

Record Sticky2DConstraints := {
  axis_x : StickyAxisConstraint;
  axis_y : StickyAxisConstraint
}.

Definition clamp_axis_shift (c : StickyAxisConstraint) : Z :=
  let clamped_min := Z.max c.(desired_shift) c.(cb_min_shift) in
  Z.min clamped_min c.(cb_max_shift).

Definition compute_sticky_2d_shift (c : Sticky2DConstraints) : Z * Z :=
  (clamp_axis_shift c.(axis_x), clamp_axis_shift c.(axis_y)).

Definition apply_2d_shift (r : PhysicalRect) (shift : Z * Z) : PhysicalRect :=
  let '(dx, dy) := shift in
  {|
    rect_x := r.(rect_x) + dx;
    rect_y := r.(rect_y) + dy;
    rect_w := r.(rect_w);
    rect_h := r.(rect_h)
  |}.

(** 1. Axis-Aligned Containment Bounds *)

Theorem axis_shift_bounded :
  forall c : StickyAxisConstraint,
    c.(cb_min_shift) <= c.(cb_max_shift) ->
    c.(cb_min_shift) <= clamp_axis_shift c <= c.(cb_max_shift).
Proof.
  intros c Hord.
  unfold clamp_axis_shift.
  split.
  - apply Z.min_glb_iff.
    split.
    + apply Z.le_max_r.
    + exact Hord.
  - apply Z.le_min_r.
Qed.

Theorem sticky_2d_shift_bounded :
  forall c : Sticky2DConstraints,
    c.(axis_x).(cb_min_shift) <= c.(axis_x).(cb_max_shift) ->
    c.(axis_y).(cb_min_shift) <= c.(axis_y).(cb_max_shift) ->
    let '(dx, dy) := compute_sticky_2d_shift c in
    (c.(axis_x).(cb_min_shift) <= dx <= c.(axis_x).(cb_max_shift)) /\
    (c.(axis_y).(cb_min_shift) <= dy <= c.(axis_y).(cb_max_shift)).
Proof.
  intros c Hx Hy.
  unfold compute_sticky_2d_shift.
  split; apply axis_shift_bounded; assumption.
Qed.

(** 2. Containing Block Containment Invariant *)

Theorem shifted_box_contained_in_cb_1d :
  forall (box_pos box_size cb_pos cb_size des : Z),
    0 <= box_size ->
    0 <= cb_size ->
    cb_pos <= box_pos ->
    box_pos + box_size <= cb_pos + cb_size ->
    let c := {| desired_shift := des; cb_min_shift := cb_pos - box_pos; cb_max_shift := (cb_pos + cb_size) - (box_pos + box_size) |} in
    let shift := clamp_axis_shift c in
    cb_pos <= box_pos + shift /\ (box_pos + shift) + box_size <= cb_pos + cb_size.
Proof.
  intros b_pos b_size cb_pos cb_size des Hbpos Hcbpos Hleft Hright.
  intros c shift.
  pose proof (axis_shift_bounded c).
  subst c shift.
  simpl in *.
  lia.
Qed.

(** 3. Shift Idempotence *)

Theorem clamp_axis_shift_idempotent :
  forall c : StickyAxisConstraint,
    c.(cb_min_shift) <= c.(cb_max_shift) ->
    let shift := clamp_axis_shift c in
    clamp_axis_shift {| desired_shift := shift; cb_min_shift := c.(cb_min_shift); cb_max_shift := c.(cb_max_shift) |} = shift.
Proof.
  intros c Hord shift.
  pose proof (axis_shift_bounded c Hord) as [Hlow Hhigh].
  unfold shift, clamp_axis_shift in *.
  simpl in *.
  lia.
Qed.
