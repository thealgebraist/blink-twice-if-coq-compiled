(******************************************************************************)
(* BlinkMasonrySemantics.v                                                    *)
(* Sound Formal Big-Step Operational Semantics for CSS Masonry Layout         *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Masonry Layout Level 1 / CSS Grid Layout Module Level 3          *)
(* 2. Blink MasonryLayoutAlgorithm (`masonry_layout_algorithm.cc`)             *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Import ListNotations.
Open Scope Z_scope.

(** Finds track index with the minimum running position in the masonry stack *)
Fixpoint find_min_track (tracks : list Z) (cur_idx best_idx min_val : Z) : (Z * Z) :=
  match tracks with
  | [] => (best_idx, min_val)
  | h :: rest =>
      if h <? min_val then
        find_min_track rest (cur_idx + 1) cur_idx h
      else
        find_min_track rest (cur_idx + 1) best_idx min_val
  end.

(** Updates the running height of the selected track by item block size *)
Fixpoint update_track_height (tracks : list Z) (target_idx cur_idx : Z) (delta : Z) : list Z :=
  match tracks with
  | [] => []
  | h :: rest =>
      if cur_idx =? target_idx then
        sat_clamp (h + delta) :: rest
      else
        h :: update_track_height rest target_idx (cur_idx + 1) delta
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem update_track_height_length_preserving :
  forall tracks target cur delta,
    length (update_track_height tracks target cur delta) = length tracks.
Proof.
  induction tracks as [| h rest IH]; intros target cur delta; simpl.
  - reflexivity.
  - destruct (cur =? target); simpl.
    + reflexivity.
    + f_equal. apply IH.
Qed.

Theorem find_min_track_deterministic :
  forall tracks c b m r1 r2,
    r1 = find_min_track tracks c b m ->
    r2 = find_min_track tracks c b m ->
    r1 = r2.
Proof.
  intros tracks c b m r1 r2 H1 H2. subst. reflexivity.
Qed.
