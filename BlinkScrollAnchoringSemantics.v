(**
  BlinkScrollAnchoringSemantics.v
  Formal specification of Chromium Blink scroll anchoring drift calculation
  derived from third_party/blink/renderer/core/page/scrolling/scroll_anchor.cc
  according to W3C Scroll Anchoring Module Level 1 (§3 Anchor Node Selection & Drift Adjustment).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record AnchorGeometry := {
  anchor_top : Z
}.

Definition compute_scroll_drift (saved current : AnchorGeometry) : Z :=
  current.(anchor_top) - saved.(anchor_top).

Definition adjust_scroll_offset
    (s_old drift s_min s_max : Z) : Z :=
  let target := s_old + drift in
  Z.max s_min (Z.min target s_max).

Definition visual_viewport_offset (anchor_top scroll_offset : Z) : Z :=
  anchor_top - scroll_offset.

(** 1. Exact Compensation Invariant (Unclamped Domain) *)

Theorem scroll_drift_exact_visual_compensation :
  forall (saved current : AnchorGeometry) (s_old : Z),
    let drift := compute_scroll_drift saved current in
    let s_new := s_old + drift in
    visual_viewport_offset current.(anchor_top) s_new =
    visual_viewport_offset saved.(anchor_top) s_old.
Proof.
  intros saved current s_old drift s_new.
  unfold s_new, drift, compute_scroll_drift, visual_viewport_offset.
  lia.
Qed.

(** 2. Zero-Drift Identity *)

Theorem zero_drift_when_anchor_unmoved :
  forall (anchor : AnchorGeometry),
    compute_scroll_drift anchor anchor = 0.
Proof.
  intros [a_top].
  unfold compute_scroll_drift.
  simpl. lia.
Qed.

Theorem zero_drift_preserves_scroll_offset :
  forall (anchor : AnchorGeometry) (s_old s_min s_max : Z),
    s_min <= s_old <= s_max ->
    adjust_scroll_offset s_old (compute_scroll_drift anchor anchor) s_min s_max = s_old.
Proof.
  intros anchor s_old s_min s_max Hbounds.
  rewrite zero_drift_when_anchor_unmoved.
  unfold adjust_scroll_offset.
  assert (s_old + 0 = s_old) by lia.
  rewrite H.
  lia.
Qed.

(** 3. Clamping Bounds Invariant *)

Theorem adjusted_scroll_offset_in_bounds :
  forall (s_old drift s_min s_max : Z),
    s_min <= s_max ->
    s_min <= adjust_scroll_offset s_old drift s_min s_max <= s_max.
Proof.
  intros s_old drift s_min s_max Hord.
  unfold adjust_scroll_offset.
  split.
  - apply Z.le_max_l.
  - apply Z.max_lub.
    + exact Hord.
    + apply Z.le_min_r.
Qed.

