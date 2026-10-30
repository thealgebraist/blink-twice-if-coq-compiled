(* =========================================================================
   BlinkGridTrackPhase1Semantics.v
   Formalization of Chromium Blink Grid Track Sizing Phase 1 Intrinsic Growth
   Source: third_party/blink/renderer/core/layout/grid/grid_track_collection.cc
           third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc
   Specification: W3C CSS Grid Layout Module Level 1 §11.5.1 & §11.5.2
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Definition kInfinitySentinel : Z := -64.

Record GridTrackState : Type := mkGridTrackState {
  gts_base_size : Z;
  gts_growth_limit : Z
}.

Definition distribute_spanning_item_to_base_sizes
    (b1 : Z) (b2 : Z) (item_intrinsic_min : Z) : Z * Z :=
  let current_sum := b1 + b2 in
  let delta := Z.max 0 (item_intrinsic_min - current_sum) in
  let d1 := delta / 2 in
  let d2 := delta - d1 in
  (b1 + d1, b2 + d2).

Theorem track_base_sizes_non_decreasing :
  forall b1 b2 item_min,
    let (b1', b2') := distribute_spanning_item_to_base_sizes b1 b2 item_min in
    b1 <= b1' /\ b2 <= b2'.
Proof.
  intros b1 b2 item_min.
  unfold distribute_spanning_item_to_base_sizes.
  set (delta := Z.max 0 (item_min - (b1 + b2))).
  assert (Hpos : 0 <= delta) by (apply Z.le_max_l).
  assert (Hd1 : 0 <= delta / 2) by (apply Z.div_pos; lia).
  assert (Hd2 : 0 <= delta - delta / 2).
  { assert (delta / 2 <= delta) by (apply Z.div_le_upper_bound; lia). lia. }
  split; lia.
Qed.

Theorem spanned_tracks_satisfy_intrinsic_min :
  forall b1 b2 item_min,
    0 <= b1 ->
    0 <= b2 ->
    let (b1', b2') := distribute_spanning_item_to_base_sizes b1 b2 item_min in
    item_min <= b1' + b2'.
Proof.
  intros b1 b2 item_min H1 H2.
  unfold distribute_spanning_item_to_base_sizes.
  set (delta := Z.max 0 (item_min - (b1 + b2))).
  assert (Hsum : (b1 + delta / 2) + (b2 + (delta - delta / 2)) = (b1 + b2) + delta) by lia.
  rewrite Hsum.
  pose proof (Z.le_max_r 0 (item_min - (b1 + b2))).
  lia.
Qed.

Theorem track_base_size_deficit_conservation :
  forall b1 b2 item_min,
    let current_sum := b1 + b2 in
    let delta := Z.max 0 (item_min - current_sum) in
    let (b1', b2') := distribute_spanning_item_to_base_sizes b1 b2 item_min in
    (b1' + b2') - current_sum = delta.
Proof.
  intros b1 b2 item_min.
  unfold distribute_spanning_item_to_base_sizes.
  lia.
Qed.

Theorem distribute_spanning_item_deterministic :
  forall b1 b2 min_s r1 r2,
    r1 = distribute_spanning_item_to_base_sizes b1 b2 min_s ->
    r2 = distribute_spanning_item_to_base_sizes b1 b2 min_s ->
    r1 = r2.
Proof.
  intros b1 b2 min_s r1 r2 H1 H2.
  subst. reflexivity.
Qed.

