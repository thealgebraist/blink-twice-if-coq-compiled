(* =========================================================================
   BlinkMinMaxSizesSemantics.v
   Formalization of Chromium Blink Intrinsic Min/Max Sizes & Clamping
   Source: third_party/blink/renderer/core/layout/min_max_sizes.cc
   Specification: W3C CSS Box Sizing Module Level 3 §5
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

(* 26.6 Fixed-Point Saturation Constants *)
Definition kInt32Min : Z := -2147483648.
Definition kInt32Max : Z := 2147483647.

Definition sat_clamp (x : Z) : Z :=
  if x <? kInt32Min then kInt32Min
  else if x >? kInt32Max then kInt32Max
  else x.

Record MinMaxSizes : Type := mkMinMaxSizes {
  mms_min : Z;
  mms_max : Z
}.

Definition add_scalar (m : MinMaxSizes) (delta : Z) : MinMaxSizes :=
  mkMinMaxSizes (sat_clamp (m.(mms_min) + delta)) (sat_clamp (m.(mms_max) + delta)).

Definition encompass (a b : MinMaxSizes) : MinMaxSizes :=
  mkMinMaxSizes (Z.max a.(mms_min) b.(mms_min)) (Z.max a.(mms_max) b.(mms_max)).

Definition clamp_to_min_max (val : Z) (m : MinMaxSizes) : Z :=
  Z.max m.(mms_min) (Z.min val m.(mms_max)).

Theorem encompass_comm :
  forall a b,
    encompass a b = encompass b a.
Proof.
  intros a b.
  unfold encompass.
  rewrite (Z.max_comm (mms_min a) (mms_min b)).
  rewrite (Z.max_comm (mms_max a) (mms_max b)).
  reflexivity.
Qed.

Theorem encompass_assoc :
  forall a b c,
    encompass a (encompass b c) = encompass (encompass a b) c.
Proof.
  intros a b c.
  unfold encompass. simpl.
  rewrite (Z.max_assoc (mms_min a) (mms_min b) (mms_min c)).
  rewrite (Z.max_assoc (mms_max a) (mms_max b) (mms_max c)).
  reflexivity.
Qed.

Theorem encompass_preserves_ordering :
  forall a b,
    a.(mms_min) <= a.(mms_max) ->
    b.(mms_min) <= b.(mms_max) ->
    (encompass a b).(mms_min) <= (encompass a b).(mms_max).
Proof.
  intros a b Ha Hb.
  unfold encompass. simpl.
  apply Z.max_le_compat; assumption.
Qed.

Theorem clamp_to_min_max_bounds :
  forall val m,
    m.(mms_min) <= m.(mms_max) ->
    m.(mms_min) <= clamp_to_min_max val m <= m.(mms_max).
Proof.
  intros val m Horder.
  unfold clamp_to_min_max.
  split.
  - apply Z.le_max_l.
  - apply Z.max_lub.
    + exact Horder.
    + apply Z.le_min_r.
Qed.

Theorem clamp_to_min_max_deterministic :
  forall val m c1 c2,
    c1 = clamp_to_min_max val m ->
    c2 = clamp_to_min_max val m ->
    c1 = c2.
Proof.
  intros val m c1 c2 H1 H2.
  subst. reflexivity.
Qed.

