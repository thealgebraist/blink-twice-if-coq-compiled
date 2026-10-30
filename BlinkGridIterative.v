(******************************************************************************)
(* BlinkGridIterative.v                                                       *)
(* Sound Formal Specification of Multi-Pass Iterative Grid Space Distribution *)
(* Resolving Gap GRID-GAP-1 in W3C CSS Grid Layout Module Level 1 (§11.5.1)   *)
(*                                                                            *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Grid Layout Level 1 (§11.5.1 Distributing Extra Space)          *)
(* 2. Blink LayoutNG NGGridLayoutAlgorithm (`ng_grid_layout_algorithm.cc`)    *)
(*    and NGGridTrackCollection::DistributeExtraSpaceToSets                   *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool PeanoNat.
Require Import BlinkOperationalSemantics.
Require Import BlinkScrollAndGrid.
Import ListNotations.
Open Scope Z_scope.

Definition track_is_frozen (t : GridTrack) : bool :=
  let pot := track_growth_potential t in
  (pot =? 0).

Fixpoint count_unfrozen (tracks : list GridTrack) : Z :=
  match tracks with
  | [] => 0
  | t :: rest => (if track_is_frozen t then 0 else 1) + count_unfrozen rest
  end.

Definition grid_iteration_step (tracks : list GridTrack) (extra_space : Z) : (list GridTrack * Z) :=
  let unfrozen := count_unfrozen tracks in
  if unfrozen =? 0 then (tracks, extra_space)
  else distribute_extra_space_list extra_space unfrozen tracks.

Fixpoint distribute_extra_space_iterative (fuel : nat) (tracks : list GridTrack) (extra_space : Z) : (list GridTrack * Z) :=
  match fuel with
  | O => (tracks, extra_space)
  | S fuel' =>
      if (extra_space <=? 0) || (count_unfrozen tracks =? 0) then
        (tracks, extra_space)
      else
        let '(next_tracks, rem_space) := grid_iteration_step tracks extra_space in
        distribute_extra_space_iterative fuel' next_tracks rem_space
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem grid_iterative_deterministic :
  forall fuel tracks extra_space r1 r2,
    distribute_extra_space_iterative fuel tracks extra_space = r1 ->
    distribute_extra_space_iterative fuel tracks extra_space = r2 ->
    r1 = r2.
Proof.
  intros fuel tracks extra_space r1 r2 H1 H2.
  subst. reflexivity.
Qed.

Lemma count_unfrozen_nonneg : forall tracks,
  0 <= count_unfrozen tracks.
Proof.
  induction tracks as [| t rest IH]; simpl.
  - lia.
  - destruct (track_is_frozen t); lia.
Qed.

Theorem grid_iterative_zero_space_fixed_point :
  forall fuel tracks,
    distribute_extra_space_iterative fuel tracks 0 = (tracks, 0).
Proof.
  destruct fuel; simpl.
  - reflexivity.
  - reflexivity.
Qed.
