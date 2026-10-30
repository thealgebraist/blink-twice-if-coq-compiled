(* =========================================================================
   BlinkMasonryPlacementSemantics.v
   Formalization of Chromium Blink CSS Masonry Item Placement Modes (pack vs next)
   Source: third_party/blink/renderer/core/layout/grid/masonry_layout_algorithm.cc
   Specification: W3C CSS Masonry Layout Module Level 1 §3
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive MasonryAutoFlow : Type :=
  | MasonryFlowPack
  | MasonryFlowNext.

Definition next_track_index (prev_track : nat) (track_count : nat) : nat :=
  (S prev_track) mod track_count.

Definition pack_track_index_2tracks (h0 : Z) (h1 : Z) : nat :=
  if h0 <=? h1 then 0%nat else 1%nat.

Definition update_placed_track_height (cur_h : Z) (item_outer_h : Z) : Z :=
  cur_h + item_outer_h.

Theorem next_track_bounded :
  forall prev_track track_count,
    (0 < track_count)%nat ->
    (next_track_index prev_track track_count < track_count)%nat.
Proof.
  intros prev_track track_count Hpos.
  unfold next_track_index.
  apply Nat.mod_upper_bound.
  lia.
Qed.

Theorem pack_track_index_2tracks_bounded :
  forall h0 h1,
    (pack_track_index_2tracks h0 h1 < 2)%nat.
Proof.
  intros h0 h1.
  unfold pack_track_index_2tracks.
  destruct (h0 <=? h1); lia.
Qed.

Theorem placed_track_height_increases :
  forall cur_h item_h,
    0 <= item_h ->
    cur_h <= update_placed_track_height cur_h item_h.
Proof.
  intros cur_h item_h Hpos.
  unfold update_placed_track_height.
  lia.
Qed.

Theorem update_placed_track_height_deterministic :
  forall ch ih h1 h2,
    h1 = update_placed_track_height ch ih ->
    h2 = update_placed_track_height ch ih ->
    h1 = h2.
Proof.
  intros ch ih h1 h2 H1 H2.
  subst. reflexivity.
Qed.

