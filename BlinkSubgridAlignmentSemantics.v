(**
  BlinkSubgridAlignmentSemantics.v
  Formal specification of Chromium Blink CSS subgrid track alignment and span sizing
  derived from third_party/blink/renderer/core/layout/grid/grid_data.h and grid_layout_algorithm.cc
  according to W3C CSS Grid Layout Module Level 2 (§2 Subgrids: Inheriting Parent Grid Tracks).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record SubgridSpan := {
  span_start : Z;
  span_end : Z
}.

Definition subgrid_track_count (sp : SubgridSpan) : Z :=
  sp.(span_end) - sp.(span_start).

Definition translate_subgrid_track (sp : SubgridSpan) (local_idx : Z) : Z :=
  sp.(span_start) + local_idx.

Definition translate_subgrid_span
    (sp : SubgridSpan) (local_s local_e : Z) : Z * Z :=
  (sp.(span_start) + local_s, sp.(span_start) + local_e).

Definition compute_track_mbp_absorption
    (local_idx : Z) (total_local_tracks : Z) (mbp_start mbp_end : Z) : Z :=
  if total_local_tracks <=? 1 then
    mbp_start + mbp_end
  else if local_idx =? 0 then
    mbp_start
  else if local_idx =? total_local_tracks - 1 then
    mbp_end
  else
    0.

(** 1. Coordinate Mapping & Span Containment Invariants *)

Theorem subgrid_translation_preserves_span_length :
  forall (sp : SubgridSpan) (local_s local_e : Z),
    let '(ps, pe) := translate_subgrid_span sp local_s local_e in
    pe - ps = local_e - local_s.
Proof.
  intros sp local_s local_e.
  unfold translate_subgrid_span.
  simpl. lia.
Qed.

Theorem subgrid_item_contained_in_parent_span :
  forall (sp : SubgridSpan) (local_s local_e : Z),
    0 <= local_s ->
    local_s <= local_e ->
    local_e <= subgrid_track_count sp ->
    let '(ps, pe) := translate_subgrid_span sp local_s local_e in
    sp.(span_start) <= ps /\ pe <= sp.(span_end).
Proof.
  intros sp local_s local_e Hpos Hord Hfit.
  unfold translate_subgrid_span, subgrid_track_count in *.
  simpl.
  split; lia.
Qed.

(** 2. Nested Subgrid Associativity Invariant *)

Theorem nested_subgrid_translation_assoc :
  forall (s_a s_b i : Z),
    s_a + (s_b + i) = (s_a + s_b) + i.
Proof.
  intros s_a s_b i.
  lia.
Qed.

(** 3. MBP Absorption Non-negativity *)

Theorem mbp_absorption_nonneg :
  forall (idx total mbp_s mbp_e : Z),
    0 <= mbp_s ->
    0 <= mbp_e ->
    0 <= compute_track_mbp_absorption idx total mbp_s mbp_e.
Proof.
  intros idx total mbp_s mbp_e Hs He.
  unfold compute_track_mbp_absorption.
  destruct (total <=? 1); [lia|].
  destruct (idx =? 0); [lia|].
  destruct (idx =? total - 1); [lia|].
  lia.
Qed.

