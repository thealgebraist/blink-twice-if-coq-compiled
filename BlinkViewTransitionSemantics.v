(* =========================================================================
   BlinkViewTransitionSemantics.v
   Formalization of Chromium Blink View Transition Snapshot Sizing & Geometry
   Source: third_party/blink/renderer/core/layout/view_transition_layout_algorithm.cc
           third_party/blink/renderer/core/layout/layout_view_transition_content.cc
   Specification: W3C CSS View Transitions Module Level 1 §3
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

Record PhysicalSize : Type := mkPhysicalSize {
  ps_width : Z;
  ps_height : Z
}.

Record SnapshotGeometry : Type := mkSnapshotGeometry {
  snap_intrinsic_width : Z;
  snap_intrinsic_height : Z;
  snap_target_width : Z;
  snap_target_height : Z
}.

(* Fixed-point scale factor computation with base 1000 *)
Definition compute_snapshot_scale_x (g : SnapshotGeometry) : Z :=
  if g.(snap_intrinsic_width) =? 0 then 1000
  else sat_clamp ((g.(snap_target_width) * 1000) / g.(snap_intrinsic_width)).

Definition compute_snapshot_scale_y (g : SnapshotGeometry) : Z :=
  if g.(snap_intrinsic_height) =? 0 then 1000
  else sat_clamp ((g.(snap_target_height) * 1000) / g.(snap_intrinsic_height)).

Definition resolve_view_transition_content_size
    (intrinsic_w : Z) (intrinsic_h : Z) (group_w : Z) (group_h : Z) : PhysicalSize :=
  mkPhysicalSize (sat_clamp (Z.max 0 group_w)) (sat_clamp (Z.max 0 group_h)).

Theorem view_transition_sizing_deterministic :
  forall iw ih gw gh s1 s2,
    s1 = resolve_view_transition_content_size iw ih gw gh ->
    s2 = resolve_view_transition_content_size iw ih gw gh ->
    s1 = s2.
Proof.
  intros iw ih gw gh s1 s2 H1 H2.
  subst. reflexivity.
Qed.

Theorem view_transition_content_size_nonneg :
  forall iw ih gw gh,
    0 <= (resolve_view_transition_content_size iw ih gw gh).(ps_width) /\
    0 <= (resolve_view_transition_content_size iw ih gw gh).(ps_height).
Proof.
  intros iw ih gw gh.
  unfold resolve_view_transition_content_size.
  simpl.
  split; unfold sat_clamp.
  - destruct (Z.max 0 gw <? kInt32Min) eqn:Emin.
    + apply Z.ltb_lt in Emin.
      unfold kInt32Min in Emin.
      pose proof (Z.le_max_l 0 gw). lia.
    + destruct (Z.max 0 gw >? kInt32Max) eqn:Emax.
      * unfold kInt32Max. lia.
      * apply Z.le_max_l.
  - destruct (Z.max 0 gh <? kInt32Min) eqn:Emin.
    + apply Z.ltb_lt in Emin.
      unfold kInt32Min in Emin.
      pose proof (Z.le_max_l 0 gh). lia.
    + destruct (Z.max 0 gh >? kInt32Max) eqn:Emax.
      * unfold kInt32Max. lia.
      * apply Z.le_max_l.
Qed.

Theorem snapshot_identity_scale_preserves_size :
  forall w h,
    0 < w ->
    w <= kInt32Max / 1000 ->
    compute_snapshot_scale_x (mkSnapshotGeometry w h w h) = 1000.
Proof.
  intros w h Hpos Hbound.
  unfold compute_snapshot_scale_x. simpl.
  assert (Hw0 : (w =? 0) = false).
  { apply Z.eqb_neq. lia. }
  rewrite Hw0.
  replace (w * 1000) with (1000 * w) by lia.
  rewrite Z.div_mul by lia.
  unfold sat_clamp, kInt32Min, kInt32Max.
  reflexivity.
Qed.
