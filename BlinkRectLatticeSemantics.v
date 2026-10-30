(* =========================================================================
   BlinkRectLatticeSemantics.v
   Formalization of Chromium Blink 2D Rect Lattices & Bounding Box Algebra
   Source: third_party/blink/renderer/core/layout/geometry/physical_rect.cc
           third_party/blink/renderer/core/layout/geometry/logical_rect.cc
   Specification: CSS 2.1 §8 Box Dimensions & SVG 2 §7.5 Bounding Boxes
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Record Interval1D : Type := mkInterval1D {
  iv_start : Z;
  iv_end : Z
}.

Definition unite_interval (a b : Interval1D) : Interval1D :=
  mkInterval1D (Z.min a.(iv_start) b.(iv_start)) (Z.max a.(iv_end) b.(iv_end)).

Definition intersect_interval (a b : Interval1D) : Interval1D :=
  let s := Z.max a.(iv_start) b.(iv_start) in
  let e := Z.min a.(iv_end) b.(iv_end) in
  if s <? e then mkInterval1D s e else mkInterval1D 0 0.

Theorem unite_interval_comm :
  forall a b,
    unite_interval a b = unite_interval b a.
Proof.
  intros a b.
  unfold unite_interval.
  rewrite (Z.min_comm (iv_start a) (iv_start b)).
  rewrite (Z.max_comm (iv_end a) (iv_end b)).
  reflexivity.
Qed.

Theorem unite_interval_assoc :
  forall a b c,
    unite_interval a (unite_interval b c) = unite_interval (unite_interval a b) c.
Proof.
  intros a b c.
  unfold unite_interval. simpl.
  rewrite (Z.min_assoc (iv_start a) (iv_start b) (iv_start c)).
  rewrite (Z.max_assoc (iv_end a) (iv_end b) (iv_end c)).
  reflexivity.
Qed.

Theorem unite_interval_idem :
  forall a,
    unite_interval a a = a.
Proof.
  intros [s e].
  unfold unite_interval. simpl.
  rewrite Z.min_id.
  rewrite Z.max_id.
  reflexivity.
Qed.

Theorem unite_interval_bounds_left :
  forall a b,
    (unite_interval a b).(iv_start) <= a.(iv_start) /\
    a.(iv_end) <= (unite_interval a b).(iv_end).
Proof.
  intros a b.
  unfold unite_interval. simpl.
  split.
  - apply Z.le_min_l.
  - apply Z.le_max_l.
Qed.

Theorem unite_interval_bounds_right :
  forall a b,
    (unite_interval a b).(iv_start) <= b.(iv_start) /\
    b.(iv_end) <= (unite_interval a b).(iv_end).
Proof.
  intros a b.
  unfold unite_interval. simpl.
  split.
  - apply Z.le_min_r.
  - apply Z.le_max_r.
Qed.

Theorem unite_interval_deterministic :
  forall a b r1 r2,
    r1 = unite_interval a b ->
    r2 = unite_interval a b ->
    r1 = r2.
Proof.
  intros a b r1 r2 H1 H2.
  subst. reflexivity.
Qed.

