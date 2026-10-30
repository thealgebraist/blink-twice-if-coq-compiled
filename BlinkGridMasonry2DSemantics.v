(**
  BlinkGridMasonry2DSemantics.v
  Formal specification of Chromium Blink grid masonry 2D auto-placement and definite tracks
  derived from third_party/blink/renderer/core/layout/grid/masonry_layout_algorithm.cc
  according to W3C CSS Grid 3 / Masonry Layout Module (§2 Masonry Axis & Grid Axis Auto-Placement).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record MasonryItem := {
  item_span : Z;
  item_masonry_size : Z;
  definite_start : option Z
}.

(** 1. Span Boundedness and Clamping *)

Definition clamp_span (span total_tracks : Z) : Z :=
  if total_tracks <=? 0 then 1
  else Z.max 1 (Z.min span total_tracks).

Theorem clamp_span_bounds :
  forall (span total_tracks : Z),
    0 < total_tracks ->
    1 <= clamp_span span total_tracks <= total_tracks.
Proof.
  intros span total_tracks Htracks.
  unfold clamp_span.
  destruct (total_tracks <=? 0) eqn:E0; [lia|].
  split.
  - apply Z.le_max_l.
  - apply Z.max_lub; [lia | apply Z.le_min_r].
Qed.

Theorem span_window_within_track_count :
  forall (start span total_tracks : Z),
    0 <= start ->
    1 <= span ->
    start <= total_tracks - span ->
    start + span <= total_tracks.
Proof.
  intros start span total_tracks Hstart Hspan Hbound.
  lia.
Qed.

(** 2. Track Height Vector Update & Monotonicity *)

Fixpoint update_track_heights
    (tracks : list Z) (start span new_h : Z) (current_idx : Z) : list Z :=
  match tracks with
  | [] => []
  | h :: rest =>
      let is_in_span := (start <=? current_idx) && (current_idx <? start + span) in
      let updated_h := if is_in_span then Z.max h new_h else h in
      updated_h :: update_track_heights rest start span new_h (current_idx + 1)
  end.

Theorem update_track_heights_preserves_length :
  forall (tracks : list Z) (start span new_h cur : Z),
    length (update_track_heights tracks start span new_h cur) = length tracks.
Proof.
  induction tracks as [|h rest IH].
  - intros. simpl. reflexivity.
  - intros. simpl.
    f_equal.
    apply IH.
Qed.

Theorem update_track_heights_monotonic :
  forall (tracks : list Z) (start span new_h cur : Z),
    Forall2 (fun h_old h_new => h_old <= h_new)
            tracks
            (update_track_heights tracks start span new_h cur).
Proof.
  induction tracks as [|h rest IH].
  - intros. simpl. constructor.
  - intros. simpl.
    constructor.
    + destruct ((start <=? cur) && (cur <? start + span)); [apply Z.le_max_l | lia].
    + apply IH.
Qed.

(** 3. Placement Definite vs Automatic *)

Definition resolve_placement_start (it : MasonryItem) (best_auto_start total_tracks : Z) : Z :=
  match it.(definite_start) with
  | Some def_s =>
      let sp := clamp_span it.(item_span) total_tracks in
      Z.max 0 (Z.min def_s (total_tracks - sp))
  | None => best_auto_start
  end.

Theorem definite_start_clamped_within_bounds :
  forall (it : MasonryItem) (def_s best_auto total_tracks : Z),
    0 < total_tracks ->
    it.(definite_start) = Some def_s ->
    let sp := clamp_span it.(item_span) total_tracks in
    0 <= resolve_placement_start it best_auto total_tracks <= total_tracks - sp.
Proof.
  intros it def_s best_auto total_tracks Htracks Hdef sp.
  unfold resolve_placement_start.
  rewrite Hdef.
  unfold sp.
  pose proof (clamp_span_bounds it.(item_span) total_tracks Htracks) as [Hsp1 Hsp2].
  assert (Hmax_bound : 0 <= total_tracks - clamp_span (item_span it) total_tracks) by lia.
  split.
  - apply Z.le_max_l.
  - apply Z.max_lub.
    + exact Hmax_bound.
    + apply Z.le_min_r.
Qed.

