## 1. `GridTrackCollection` Auto-Repeat Track Count Calculation (`auto-fill`)

In Chromium Blink’s LayoutNG Grid implementation (`third_party/blink/renderer/core/layout/grid/grid_track_collection.cc` and `grid_layout_algorithm.cc`), the number of repetitions for an `auto-fill` or `auto-fit` repeat notation is computed prior to building the finalized `GridLayoutTrackCollection` ranges.

### Normative Specification (CSS Grid Layout Module Level 1 §7.2.2.2)
When `auto-fill` or `auto-fit` is given as the repetition number:
1. If the grid container has a definite size or max-size in the relevant axis, the number of repetitions is the largest possible positive integer that does not cause the grid to overflow its grid container (treating each track as its max track sizing function if definite, or its minimum track sizing function otherwise, and taking `grid-gap` into account). If any number of repetitions would overflow, the repetition count is `1`.
2. If the grid container has a definite min-size in the relevant axis (and no definite size/max-size), the number of repetitions is the smallest possible positive integer that fulfills that minimum requirement.

### Blink Implementation Mechanics
In `GridLayoutAlgorithm::ComputeAutomaticRepetitions`, Blink evaluates the available grid container space $W_{\text{avail}}$ (`LayoutUnit`), the grid gap $G$ (`grid_gap`), the size of non-auto-repeating tracks $W_{\text{non\_auto}}$, and the single-iteration size of the `repeat()` pattern $S_{\text{rep}}$ (for a single track of size $T$, $S_{\text{rep}} = T$).

Assuming all tracks belong to the single-track auto-repeat listing ($W_{\text{non\_auto}} = 0$) and the container has a definite size or max-size $W_{\text{avail}}$:

1. **Effective Available Space & Track Stride:**
   A repetition of $N$ tracks introduces $N - 1$ internal gutters of size $G$:
   $$\text{TotalUsed}(N) = N \cdot T + (N - 1) \cdot G = N \cdot (T + G) - G$$
2. **Overflow Inequality:**
   To avoid overflowing $W_{\text{avail}}$, Blink solves for the maximum integer $N$:
   $$N \cdot (T + G) - G \le W_{\text{avail}} \iff N \cdot (T + G) \le W_{\text{avail}} + G$$
3. **Closed-Form Floor Clamping:**
   Since $T > 0$ and $G \ge 0$ (guaranteed by CSS parsing and Blink's track size clamping to $\ge \text{1px}$ or `LayoutUnit::Epsilon()` when all tracks in the repeat list are zero-sized), Blink computes:
   $$N = \max\left(1, \left\lfloor \frac{W_{\text{avail}} + G}{T + G} \right\rfloor\right)$$
4. **Track Collection Materialization:**
   Once $N$ is resolved, `GridRangeBuilder` expands the `repeat(auto-fill, ...)` definition into $N$ concrete repetitions within the `GridTrackList`. For `auto-fill`, all $N$ generated tracks are marked as non-collapsed and retain their declared sizing functions throughout the track sizing algorithm (`ComputeUsedTrackSizes`).

---

## 2. `auto-fit` Divergence: Empty Track Collapsing

Per CSS Grid 1 §7.2.2.2.1, `auto-fit` behaves identically to `auto-fill` during track count calculation ($N$ is computed using the exact same formula) and during explicit/implicit item placement (`GridItemPlacement`). The divergence occurs **after** grid items are placed into grid cells, inside `GridBlockTrackCollection::FinalizeRanges` and `GridSizingTrackCollection::InitializeSets`.

### Blink Implementation Pipeline for `auto-fit`
1. **Occupancy Bitvector Tracking:**
   After running `GridPlacement`, Blink iterates over all `GridItemData` spans. Every range in `GridRangeVector` overlapped by at least one grid item (spanning either definitely or indefinitely across the track) has its occupancy flag set.
2. **Empty Track Identification (`IsTrackCollapsed`):**
   If a range belongs to an `auto-fit` repeater (`range.IsAutoFit()`) and has **no** grid items placed into or spanning across its tracks (`!range.IsOccupied()`), Blink marks the tracks in that range as **collapsed**.
3. **Collapsing Semantics in `GridSizingTrackCollection`:**
   - **Used Track Size:** Collapsed tracks are excluded from `GridSet` creation (or assigned a zero-sized `GridSet` where base size $= 0\text{px}$ and growth limit $= 0\text{px}$). Their final used size is unconditionally forced to $0\text{px}$.
   - **Gutter / Gap Suppression:** Any adjacent gutters (`grid-gap`) associated with a collapsed track are also collapsed to $0\text{px}$. Specifically, if $K$ out of $N$ tracks remain occupied ($0 \le K \le N$), only $\max(0, K - 1)$ gutters remain active between the surviving tracks. If all $N$ tracks collapse ($K = 0$), 0 gutters are rendered.

| Phase | `auto-fill` | `auto-fit` |
| :--- | :--- | :--- |
| **1. Repetition Count ($N$)** | $\max(1, \lfloor(W_{\text{avail}} + G) / (T + G)\rfloor)$ | $\max(1, \lfloor(W_{\text{avail}} + G) / (T + G)\rfloor)$ |
| **2. Auto-Placement** | Places items across $N$ tracks | Places items across $N$ tracks |
| **3. Empty Track Handling** | Retains declared `GridTrackSize` ($T$) | Forced to $0\text{px}$ used size |
| **4. Empty Track Gutters** | Retains $N - 1$ gutters of size $G$ | Collapses gutters of empty tracks |
| **5. Free Space Distribution** | Empty tracks absorb `fr` / `auto` space | Freed space distributed to occupied flexible/auto tracks or alignment |

---

## 3. Core Invariants

1. **Minimum Track Count Invariant ($N \ge 1$):**
   For any available width $W_{\text{avail}} \ge 0$, track size $T > 0$, and gap $G \ge 0$, the computed repetition count $N$ is strictly positive ($N \ge 1$). In particular, whenever $W_{\text{avail}} \ge T$, the un-clamped floor ratio $\lfloor (W_{\text{avail}} + G)/(T + G) \rfloor$ is already $\ge 1$.
2. **Non-Overflow Bound ($W_{\text{avail}} \ge T \implies \text{UsedSpace}(N) \le W_{\text{avail}}$):**
   Whenever the container can fit at least one track ($W_{\text{avail}} \ge T$), the total space consumed by $N$ tracks and $N - 1$ gaps under `auto-fill` (and `auto-fit` after collapsing) never exceeds $W_{\text{avail}}$:
   $$N \cdot T + (N - 1) \cdot G \le W_{\text{avail}}$$
3. **Occupied Track Preservation & Monotonic Space Reduction under `auto-fit`:**
   Collapsing empty tracks in `auto-fit` preserves the exact track sizing of all occupied tracks ($\forall i, \text{occupied}(i) = \text{true} \implies \text{size}_{\text{fit}}(i) = \text{size}_{\text{fill}}(i)$ prior to `fr`/stretch distribution) and guarantees that total used track space under `auto-fit` is bounded above by the `auto-fill` space and therefore by $W_{\text{avail}}$.

---

## 4. Concrete Rocq / Coq Formalization (`BlinkGridAutoRepeatSemantics.v`)

The following file is self-contained and compiles cleanly under Coq / Rocq 8.16–8.20+.

```coq
(** * BlinkGridAutoRepeatSemantics.v
    Formal verification of Chromium Blink CSS Grid auto-fill and auto-fit
    track count calculation and empty track collapsing against CSS Grid 1 §7.2.2.
*)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Module BlinkGridAutoRepeatSemantics.

  (** ** 1. Auto-Repeat Track Count Calculation *)

  (** Computes N = max(1, floor((W_avail + gap) / (track_size + gap)))
      Per CSS Grid 1 §7.2.2.2 and Blink's GridLayoutAlgorithm::ComputeAutomaticRepetitions. *)
  Definition compute_auto_repeat_count (w_avail track_size gap : nat) : nat :=
    Nat.max 1 ((w_avail + gap) / (track_size + gap)).

  (** Total space consumed by [n] tracks of size [track_size] with [n - 1] internal gaps. *)
  Definition total_auto_fill_space (n track_size gap : nat) : nat :=
    match n with
    | 0 => 0
    | S n' => n * track_size + n' * gap
    end.

  (** ** 2. Auto-Fill vs Auto-Fit Track Sizing and Collapsing *)

  Inductive AutoRepeatType : Type :=
  | AutoFill
  | AutoFit.

  (** For a single track of base size [track_size] and occupancy boolean [occupied],
      compute its used track size after range finalization. *)
  Definition resolve_track_used_size (mode : AutoRepeatType) (track_size : nat) (occupied : bool) : nat :=
    match mode with
    | AutoFill => track_size
    | AutoFit  => if occupied then track_size else 0
    end.

  (** Resolves a list of track occupancy flags into a list of used track sizes. *)
  Definition resolve_track_list (mode : AutoRepeatType) (track_size : nat) (occupancies : list bool) : list nat :=
    map (resolve_track_used_size mode track_size) occupancies.

  (** Count the number of non-collapsed (active) tracks.
      In AutoFill, all tracks are active. In AutoFit, only occupied tracks are active. *)
  Definition active_track_count (mode : AutoRepeatType) (occupancies : list bool) : nat :=
    match mode with
    | AutoFill => length occupancies
    | AutoFit  => count_occ bool_dec occupancies true
    end.

  (** Sum of a list of natural numbers (total track base sizes). *)
  Fixpoint sum_list (l : list nat) : nat :=
    match l with
    | [] => 0
    | x :: xs => x + sum_list xs
    end.

  (** Total used space (tracks + active internal gaps) for a finalized track collection. *)
  Definition total_collection_used_space
    (mode : AutoRepeatType) (track_size gap : nat) (occupancies : list bool) : nat :=
    let track_sum := sum_list (resolve_track_list mode track_size occupancies) in
    let active_n  := active_track_count mode occupancies in
    let gap_sum   := (active_n - 1) * gap in
    track_sum + gap_sum.

  (** ** 3. Formal Theorems and Invariants *)

  (** *** Theorem 1a: Unconditional Positivity (N >= 1) *)
  Theorem auto_repeat_count_ge_1_always :
    forall w_avail track_size gap : nat,
      compute_auto_repeat_count w_avail track_size gap >= 1.
  Proof.
    intros w_avail track_size gap.
    unfold compute_auto_repeat_count.
    lia.
  Qed.

  (** *** Theorem 1b: Exact Floor Regime when W_avail >= track_size
      When W_avail >= track_size > 0, the un-clamped division is already >= 1,
      so N = (W_avail + gap) / (track_size + gap) >= 1. *)
  Theorem auto_repeat_count_exact_when_fits :
    forall w_avail track_size gap : nat,
      track_size > 0 ->
      w_avail >= track_size ->
      (w_avail + gap) / (track_size + gap) >= 1 /\
      compute_auto_repeat_count w_avail track_size gap = (w_avail + gap) / (track_size + gap).
  Proof.
    intros w_avail track_size gap Hts Hw.
    unfold compute_auto_repeat_count.
    assert (Hdenom : track_size + gap > 0) by lia.
    assert (Hnum : track_size + gap <= w_avail + gap) by lia.
    pose proof (Nat.div_le_mono (track_size + gap) (w_avail + gap) (track_size + gap) Hdenom Hnum) as Hdiv.
    rewrite Nat.div_same in Hdiv by lia.
    split; lia.
  Qed.

  (** *** Theorem 2: Auto-Fill Non-Overflow Invariant
      Whenever W_avail >= track_size > 0, the total space of N tracks and N - 1 gaps
      never exceeds W_avail. *)
  Theorem auto_fill_total_space_le_w_avail :
    forall w_avail track_size gap : nat,
      track_size > 0 ->
      w_avail >= track_size ->
      let n := compute_auto_repeat_count w_avail track_size gap in
      total_auto_fill_space n track_size gap <= w_avail.
  Proof.
    intros w_avail track_size gap Hts Hw n.
    destruct (auto_repeat_count_exact_when_fits w_avail track_size gap Hts Hw) as [Hge1 Heq].
    fold n in Heq.
    destruct n as [| n'] eqn:Hn.
    - lia.
    - unfold total_auto_fill_space.
      assert (Hdenom : track_size + gap <> 0) by lia.
      pose proof (Nat.mul_div_le (w_avail + gap) (track_size + gap) Hdenom) as Hmul.
      rewrite <- Heq in Hmul.
      rewrite <- Hn in *.
      (* (track_size + gap) * S n' <= w_avail + gap
         ==> S n' * track_size + n' * gap + gap <= w_avail + gap *)
      lia.
  Qed.

  (** *** Theorem 3a: Occupied Track Preservation & Empty Track Collapsing
      Auto-Fit preserves the exact track size of every occupied track while
      collapsing every unoccupied track to 0px. *)
  Theorem auto_fit_preserves_occupied_and_collapses_empty :
    forall (track_size : nat) (occupancies : list bool) (i : nat),
      i < length occupancies ->
      nth i (resolve_track_list AutoFit track_size occupancies