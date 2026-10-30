(**
  BlinkViewTransitionSnapshotSemantics.v
  Formal specification of Chromium Blink CSS view transitions snapshot geometry and quad interpolation
  derived from third_party/blink/renderer/core/view_transition/view_transition_style_tracker.cc
  according to W3C CSS View Transitions Module Level 1 (§3 Capturing Snapshots & Geometry Transformations).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Definition kScale : Z := 1024.

Record SnapshotRect := {
  snap_x : Z;
  snap_y : Z;
  snap_w : Z;
  snap_h : Z
}.

Definition lerp_coord (c_old c_new t : Z) : Z :=
  c_old + (c_new - c_old) * t / kScale.

Definition interpolate_snapshot (r_old r_new : SnapshotRect) (t : Z) : SnapshotRect := {|
  snap_x := lerp_coord r_old.(snap_x) r_new.(snap_x) t;
  snap_y := lerp_coord r_old.(snap_y) r_new.(snap_y) t;
  snap_w := lerp_coord r_old.(snap_w) r_new.(snap_w) t;
  snap_h := lerp_coord r_old.(snap_h) r_new.(snap_h) t
|}.

Lemma lerp_coord_at_zero :
  forall c_old c_new : Z,
    lerp_coord c_old c_new 0 = c_old.
Proof.
  intros c_old c_new.
  unfold lerp_coord, kScale.
  rewrite Z.mul_0_r.
  rewrite Z.div_0_l by lia.
  lia.
Qed.

Lemma lerp_coord_at_one :
  forall c_old c_new : Z,
    lerp_coord c_old c_new kScale = c_new.
Proof.
  intros c_old c_new.
  unfold lerp_coord, kScale.
  rewrite Z.div_mul by lia.
  lia.
Qed.

(** 1. Boundary Preservation Invariants *)

Theorem snapshot_interpolation_at_zero :
  forall r_old r_new : SnapshotRect,
    interpolate_snapshot r_old r_new 0 = r_old.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold interpolate_snapshot.
  simpl.
  repeat rewrite lerp_coord_at_zero.
  reflexivity.
Qed.

Theorem snapshot_interpolation_at_one :
  forall r_old r_new : SnapshotRect,
    interpolate_snapshot r_old r_new kScale = r_new.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold interpolate_snapshot.
  simpl.
  repeat rewrite lerp_coord_at_one.
  reflexivity.
Qed.

(** 2. Non-negativity and Convexity of Interpolated Dimensions *)

Theorem snapshot_dimension_nonneg :
  forall (w_old w_new t : Z),
    0 <= w_old ->
    0 <= w_new ->
    0 <= t <= kScale ->
    0 <= lerp_coord w_old w_new t.
Proof.
  intros w_old w_new t Hw1 Hw2 Ht.
  unfold lerp_coord, kScale in *.
  destruct (Z.le_gt_cases w_old w_new).
  - assert (0 <= (w_new - w_old) * t).
    { apply Z.mul_nonneg_nonneg; lia. }
    assert (0 <= (w_new - w_old) * t / 1024).
    { apply Z.div_pos; lia. }
    lia.
  - assert (Hneg : w_new - w_old < 0) by lia.
    assert (Hmul : (w_new - w_old) * 1024 <= (w_new - w_old) * t).
    { apply Z.mul_le_mono_nonpos_l; lia. }
    assert (Hdiv : (w_new - w_old) * 1024 / 1024 <= (w_new - w_old) * t / 1024).
    { apply Z.div_le_mono; [lia | exact Hmul]. }
    rewrite Z.div_mul in Hdiv by lia.
    lia.
Qed.

Theorem snapshot_dimensions_nonneg :
  forall (r_old r_new : SnapshotRect) (t : Z),
    0 <= r_old.(snap_w) ->
    0 <= r_old.(snap_h) ->
    0 <= r_new.(snap_w) ->
    0 <= r_new.(snap_h) ->
    0 <= t <= kScale ->
    let r_interp := interpolate_snapshot r_old r_new t in
    0 <= r_interp.(snap_w) /\ 0 <= r_interp.(snap_h).
Proof.
  intros r_old r_new t Hw1 Hh1 Hw2 Hh2 Ht r_interp.
  unfold r_interp, interpolate_snapshot.
  simpl.
  split; apply snapshot_dimension_nonneg; lia.
Qed.
