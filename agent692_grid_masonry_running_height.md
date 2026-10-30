# Formal Verification Report: CSS Grid Masonry Track Allocation by Minimum Running Height

**Agent**: Formal Verification Agent 692 (W3C/WHATWG Layout Rules in Chromium Blink)  
**Topic**: Masonry layout item allocation to track with minimum running height  
**Chromium Source**: `third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc`  
**Specification**: CSS Grid Layout Module Level 3 (Masonry Layout) §4  
**Formal Theory Target**: `BlinkGridMasonryRunningHeightSemantics.v`  
**Mathematical Property**: $\text{next\_track} = \operatorname{argmin}(\text{running\_heights}); \quad \text{updated\_height} = \min\_h + \text{item\_h}$

---

## 1. Normative W3C Specification Requirements

In the **CSS Grid Layout Module Level 3** (Masonry Layout) specification, §4 (*Masonry Layout Algorithm*) defines how grid items are placed along the masonry axis when the perpendicular axis acts as a standard CSS Grid axis.

### 1.1 Normative Placement Rules
1. **Running Positions Initialization**: For each track $i \in [0, N-1]$ in the grid axis, the layout engine maintains a *running position* (or *running height* in vertical masonry), denoted $H[i]$, initialized to $0$ (or the start border/padding edge of the container).
2. **Track Selection for Single-Span Auto-Placed Items**: When placing an item with a span of $1$ that does not have an explicit track placement:
   * The algorithm identifies the minimum running position across all available tracks:
     $$H_{\min} = \min_{0 \le i < N} H[i]$$
   * **Tie-Breaking Rule**: If multiple tracks share the exact minimum running position $H_{\min}$, the algorithm MUST choose the **first** such track in layout order (i.e., the track with the smallest index $i$):
     $$i^* = \min \{ i \in [0, N-1] \mid H[i] = H_{\min} \}$$
3. **Running Position Update**: Once the item with masonry-axis margin-box size $S \ge 0$ is placed into track $i^*$, the running position of track $i^*$ is updated to:
   $$H'[i^*] = H[i^*] + S = H_{\min} + S$$
   For all other tracks $j \neq i^*$, the running position remains unchanged:
   $$H'[j] = H[j]$$

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine (LayoutNG architecture), CSS Grid and Masonry layout algorithms are implemented within `third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc` (and helper structures in `grid_item.h` / `grid_track_collection.h`).

### 2.1 Implementation Details
Blink represents layout distances and running positions using fixed-point arithmetic (`LayoutUnit`, backed by a 32-bit signed integer with $1/64$th pixel precision). During the masonry placement phase:

```cpp
// Conceptual structure of Blink's Masonry running-position tracker in grid_layout_algorithm.cc
wtf_size_t FindTrackWithMinRunningPosition(
    const Vector<LayoutUnit>& running_positions,
    LayoutUnit* out_min_position) {
  DCHECK(!running_positions.empty());
  wtf_size_t min_index = 0;
  LayoutUnit min_position = running_positions[0];

  for (wtf_size_t i = 1; i < running_positions.size(); ++i) {
    // Strictly less-than (<) enforces the W3C first-track tie-breaking rule.
    if (running_positions[i] < min_position) {
      min_position = running_positions[i];
      min_index = i;
    }
  }
  *out_min_position = min_position;
  return min_index;
}

void PlaceMasonryItem(Vector<LayoutUnit>& running_positions,
                      LayoutUnit item_masonry_size) {
  LayoutUnit min_pos;
  wtf_size_t target_track =
      FindTrackWithMinRunningPosition(running_positions, &min_pos);
  running_positions[target_track] = min_pos + item_masonry_size;
}
```

### 2.2 Critical Engine Invariants
1. **Non-Empty Track Collection**: A valid grid axis always has at least one track (`running_positions.size() >= 1`).
2. **Strict Tie-Breaking via `<`**: By using `<` rather than `<=` when scanning from index $0$ to $N-1$, Blink guarantees that `min_index` only updates when a strictly smaller running height is encountered, preserving the earliest track index on ties.
3. **Length Preservation**: Updating `running_positions[target_track]` mutates the vector in place without altering the number of tracks.
4. **Monotonicity**: For items with non-negative outer block sizes (`item_masonry_size >= 0`), running positions are monotonically non-decreasing, and the sum of all running positions increases by exactly `item_masonry_size`.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete formalization and verification module `BlinkGridMasonryRunningHeightSemantics.v`. It models `LayoutUnit` values using $\mathbb{Z}$ (`Z`), tracks as lists of $\mathbb{Z}$, and proves optimality, tie-breaking, state-update equations, and monotonicity invariants without a single `Admitted`.

## 4. Complete Rocq/Coq Formalization and Proofs

```coq
(** * BlinkGridMasonryRunningHeightSemantics.v
    Formal Verification of W3C CSS Grid Level 3 (Masonry) Track Allocation
    in Chromium Blink (grid_layout_algorithm.cc). *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import List.
From Coq Require Import Bool.
Import ListNotations.

Open Scope Z_scope.

Section MasonryRunningHeightSemantics.

  (** ** 1. Data Types and Basic Definitions *)

  (** In Blink, LayoutUnit is a fixed-point number represented as an integer. *)
  Definition LayoutUnit := Z.

  (** The running heights of the masonry tracks are represented as a list of LayoutUnits. *)
  Definition TrackHeights := list LayoutUnit.

  (** Tail-recursive accumulator representing Blink's loop over [running_positions]:
      [curr_idx] : index of the current element being inspected
      [best_idx] : index of the minimum element found so far
      [best_h]   : minimum running height found so far *)
  Fixpoint find_min_track_aux (l : TrackHeights) (curr_idx best_idx : nat) (best_h : LayoutUnit)
    : (nat * LayoutUnit) :=
    match l with
    | [] => (best_idx, best_h)
    | h :: tl =>
        if Z.ltb h best_h then
          find_min_track_aux tl (S curr_idx) curr_idx h
        else
          find_min_track_aux tl (S curr_idx) best_idx best_h
    end.

  (** Top-level function finding the (index, height) of the track with minimum running height.
      Defaults to (0, 0) only on an empty track list (which is excluded by Blink's DCHECK). *)
  Definition find_min_track (l : TrackHeights) : (nat * LayoutUnit) :=
    match l with
    | [] => (0%nat, 0)
    | h :: tl => find_min_track_aux tl 1%nat 0%nat h
    end.

  (** Update the running height at track index [idx] to [new_h]. *)
  Fixpoint update_track (l : TrackHeights) (idx : nat) (new_h : LayoutUnit) : TrackHeights :=
    match l, idx with
    | [], _ => []
    | _ :: tl, 0%nat => new_h :: tl
    | h :: tl, S idx' => h :: update_track tl idx' new_h
    end.

  (** Allocate a single-span masonry item with height [item_h] to the track collection [l].
      Returns the chosen track index, the updated track heights, and the new height of that track. *)
  Definition allocate_masonry_item (l : TrackHeights) (item_h : LayoutUnit)
    : (nat * TrackHeights * LayoutUnit) :=
    let (min_idx, min_h) := find_min_track l in
    let updated_h := min_h + item_h in
    let l' := update_track l min_idx updated_h in
    (min_idx, l', updated_h).

  (** Sum of all track running heights (used for conservation invariants). *)
  Fixpoint sum_heights (l : TrackHeights) : LayoutUnit :=
    match l with
    | [] => 0
    | h :: tl => h + sum_heights tl
    end.

  (** ** 2. Helper Lemmas for [find_min_track_aux] *)

  (** Generalized invariant for the tail-recursive scan [find_min_track_aux].
      Given a prefix [prefix] already scanned and a remaining suffix [l]:
      1. [best_idx] is a valid index in [prefix] where [best_h] resides.
      2. [best_h] is less than or equal to all heights in [prefix].
      3. [best_h] is strictly less than all heights in [prefix] before [best_idx] (tie-breaking). *)
  Lemma find_min_track_aux_spec :
    forall (l prefix : TrackHeights) (best_idx : nat) (best_h : LayoutUnit)
           (res_idx : nat) (res_h : LayoutUnit),
      find_min_track_aux l (length prefix) best_idx best_h = (res_idx, res_h) ->
      (best_idx < length prefix)%nat ->
      nth best_idx prefix 0 = best_h ->
      (forall k : nat, (k < length prefix)%nat -> best_h <= nth k prefix 0) ->
      (forall k : nat, (k < best_idx)%nat -> best_h < nth k prefix 0) ->
      (res_idx < length (prefix ++ l))%nat /\
      nth res_idx (prefix ++ l) 0 = res_h /\
      (forall k : nat, (k < length (prefix ++ l))%nat -> res_h <= nth k (prefix ++ l) 0) /\
      (forall k : nat, (k < res_idx)%nat -> res_h < nth k (prefix ++ l) 0).
  Proof.
    induction l as [| h tl IH]; intros prefix best_idx best_h res_idx res_h Hfind Hlen Hnth Hle Hlt.
    - simpl in Hfind. inversion Hfind; subst.
      rewrite app_nil_r.
      repeat split; assumption.
    - simpl in Hfind.
      destruct (Z.ltb h best_h) eqn:Hltb.
      + apply Z.ltb_lt in Hltb.
        replace (prefix ++ h :: tl) with ((prefix ++ [h]) ++ tl)
          by (rewrite <- app_assoc; reflexivity).
        apply (IH (prefix ++ [h]) (length prefix) h res_idx res_h).
        * rewrite app_length. simpl. rewrite Nat.add_1_r. exact Hfind.
        * rewrite app_length. simpl. lia.
        * rewrite app_nth2 by lia. replace (length prefix - length prefix)%nat with 0%nat by lia.
          simpl. reflexivity.
        * intros k Hk. rewrite app_length in Hk. simpl in Hk.
          destruct (Nat.eq_dec k (length prefix)) as [Heq | Hneq].
          -- subst k. rewrite app_nth2 by lia.
             replace (length prefix - length prefix)%nat with 0%nat by lia.
             simpl. lia.
          -- assert (Hk_lt : (k < length prefix)%nat) by lia.
             rewrite app_nth1 by lia.
              specialize (Hle k Hk_lt). lia.
        * intros k Hk.
          rewrite app_nth1 by lia.
          specialize (Hle k Hk). lia.
      + apply Z.ltb_ge in Hltb.
        replace (prefix ++ h :: tl) with ((prefix ++ [h]) ++ tl)
          by (rewrite <- app_assoc; reflexivity).
        apply (IH (prefix ++ [h]) best_idx best_h res_idx res_h).
        * rewrite app_length. simpl. rewrite Nat.add_1_r. exact Hfind.
        * rewrite app_length. simpl. lia.
        * rewrite app_nth1 by lia. exact Hnth.
        * intros k Hk. rewrite app_length in Hk. simpl in Hk.
          destruct (Nat.eq_dec k (length prefix)) as [Heq | Hneq].
          -- subst k. rewrite app_nth2 by lia.
             replace (length prefix - length prefix)%nat with 0%nat by lia.
             simpl. lia.
          -- assert (Hk_lt : (k < length prefix)%nat) by lia.
             rewrite app_nth1 by lia.
             apply Hle. exact Hk_lt.
        * intros k Hk.
          rewrite app_nth1 by lia.
          apply Hlt. exact Hk.
  Qed.

  (** ** 3. Main Theorems for Track Selection (argmin & Tie-Breaking) *)

  Theorem find_min_track_correct :
    forall (l : TrackHeights) (idx : nat) (min_h : LayoutUnit),
      l <> [] ->
      find_min_track l = (idx, min_h) ->
      (idx < length l)%nat /\
      nth idx l 0 = min_h /\
      (forall k : nat, (k < length l)%nat -> min_h <= nth k l 0) /\
      (forall k : nat, (k < idx)%nat -> min_h < nth k l 0).
  Proof.
    intros l idx min_h Hnonempty Hfind.
    destruct l as [| h tl].
    - contradiction.
    - simpl in Hfind.
      change (h :: tl) with ([h] ++ tl).
      apply (find_min_track_aux_spec tl [h] 0%nat h idx min_h Hfind).
      + simpl. lia.
      + simpl. reflexivity.
      + intros k Hk. simpl in Hk.
        assert (k = 0%nat) by lia. subst k. simpl. lia.
      + intros k Hk. lia.
  Qed.

  (** Uniqueness of the first-minimum index: any index satisfying both the minimum
      property and the strict prefix tie-breaking property must equal [idx]. *)
  Theorem find_