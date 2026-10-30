### 1. Gap Allocation Analysis (Blink vs. CSS Box Alignment 3 §8)

In **CSS Box Alignment Module Level 3 §8 (Gaps Between Boxes)**, the `row-gap` and `column-gap` properties specify fixed-length gutters inserted strictly *between* adjacent grid tracks. 

* **Normative Specification:** For a grid axis containing $N$ tracks, gutters are only placed between adjacent pairs $(T_i, T_{i+1})$ for $0 \le i < N - 1$. Gutters are never inserted before the first track or after the last track (edge spacing is governed by Content Distribution properties `justify-content` and `align-content`). Thus, the exact number of gaps is:
  $$\text{num\_gaps}(N) = \max(0, N - 1)$$

* **Chromium Blink Implementation (`third_party/blink/renderer/core/layout/grid/`):**
  In `GridLayoutAlgorithm` and `GridTrackSizingAlgorithm`, Blink represents the track collection via `GridSizingTrackCollection` (during sizing) and `GridLayoutTrackCollection` (during geometry positioning). When computing the grid geometry:
  1. Blink queries `TrackCount()` to determine $N$.
  2. If $N = 0$ (an empty grid axis), no gutters are allocated ($\max(0, 0 - 1) = 0$).
  3. If $N \ge 1$, exactly $N - 1$ internal boundaries exist, and `grid_gap` is applied exclusively at these $N - 1$ boundaries.

---

### 2. Total Gap Space & Available Track Space ($W_{\text{tracks}}$)

Before executing the Track Sizing Algorithm (CSS Grid Layout Module Level 2 §11.4), Blink must compute the *free space* available for track growth and percentage resolution.

* **Total Gap Space:** Given a non-negative resolved gutter size $G \ge 0$ (`LayoutUnit` in Blink), the total space consumed by gutters along an axis of $N$ tracks is:
  $$\text{Total\_gap}(N, G) = \max(0, N - 1) \times G$$

* **Available Space for Tracks ($W_{\text{tracks}}$):** Let $W_{\text{total}}$ be the definite available inner size of the grid container along the relevant axis. Per CSS Box Alignment 3 §8.1, gaps act as if they acquire an additional fixed-size track between adjacent tracks, reducing the space available for flexible (`fr`) and intrinsic track sizing. To prevent negative available space from breaking track sizing invariants when gutters exceed the container size ($W_{\text{total}} < \text{Total\_gap}$), Blink clamps the available track space at zero:
  $$W_{\text{tracks}} = \max\left(0, W_{\text{total}} - \text{Total\_gap}(N, G)\right)$$

*(Note: In Blink's `GridTrackSizingAlgorithm::ComputeAutomaticRepetitions` and `CalculateAvailableSize`, `TotalGapSize` is subtracted from the container's available size and floored at `LayoutUnit()` i.e., `0`).*

---

### 3. Offset & Span Invariants

Once track base sizes $[t_0, t_1, \dots, t_{N-1}]$ are finalized and before additional `justify-content`/`align-content` distribution offsets are injected, the baseline track and grid line geometry (`GridLayoutTrackCollection::InitializeSetsGeometry`) obeys two fundamental invariants:

1. **Strict Offset Advancement Invariant:**
   Let $O_i$ be the starting physical/logical offset of track $i$ (for $0 \le i < N$), with $O_0 = 0$ (assuming zero start-edge alignment offset). The offset of track $i+1$ advances by the exact size of track $i$ plus one gutter $G$:
   $$\forall i \in [0, N-2], \quad O_{i+1} = O_i + t_i + G$$
   Since $t_i \ge 0$ and $G \ge 0$, offsets are monotonically non-decreasing ($O_{i+1} \ge O_i$), and strictly increasing whenever $t_i + G > 0$.

2. **Total Span Conservation Invariant:**
   The total geometric span from the start of the first track ($O_0$) to the end edge of the last track ($O_{N-1} + t_{N-1}$) for any non-empty track list ($N \ge 1$) equals the sum of all track sizes plus the total gap space:
   $$\text{Span}(T, G) = O_{N-1} + t_{N-1} - O_0 = \left(\sum_{i=0}^{N-1} t_i\right) + (N - 1) \times G$$

---

### 4. Formal Verification in Rocq/Coq (`BlinkGridGapDistributionSemantics.v`)

Below is the self-contained, fully proved Rocq/Coq formalization of the Chromium Blink Grid Gap Distribution semantics and its invariants.

```coq
(** * BlinkGridGapDistributionSemantics.v
    Formal Audit of Chromium Blink Grid Gap Distribution vs CSS Box Alignment 3 §8.
    Agent 164 - Layout & Geometry Formal Verification. *)

From Coq Require Import Arith PeanoNat Lia List.
Import ListNotations.

Open Scope nat_scope.

Section BlinkGridGapDistribution.

  (** ** 1. Core Definitions: Gap Allocation & Space Partitioning *)

  (** Number of gaps between [n] tracks: max(0, n - 1).
      In Rocq's [nat], truncated subtraction [n - 1] naturally computes [max(0, n - 1)]. *)
  Definition num_gaps (n : nat) : nat :=
    n - 1.

  (** Total space occupied by gaps for [n] tracks with gutter size [gap]. *)
  Definition total_gap_space (n gap : nat) : nat :=
    (num_gaps n) * gap.

  (** Available space for tracks: W_tracks = max(0, W_total - Total_gap).
      In [nat], truncated subtraction naturally clamps at 0. *)
  Definition available_track_space (w_total n gap : nat) : nat :=
    w_total - (total_gap_space n gap).

  (** Sum of all track sizes in a track list. *)
  Fixpoint sum_tracks (tracks : list nat) : nat :=
    match tracks with
    | [] => 0
    | t :: ts => t + sum_tracks ts
    end.

  (** Compute the starting offset of each track given initial offset [curr_offset]
      and fixed gutter [gap]. Mirrors Blink's InitializeSetsGeometry accumulator. *)
  Fixpoint compute_track_offsets (tracks : list nat) (gap curr_offset : nat) : list nat :=
    match tracks with
    | [] => []
    | t :: ts => curr_offset :: compute_track_offsets ts gap (curr_offset + t + gap)
    end.

  (** Total geometric span covered by the tracks and their internal gaps. *)
  Definition total_grid_span (tracks : list nat) (gap : nat) : nat :=
    match tracks with
    | [] => 0
    | _ => sum_tracks tracks + total_gap_space (length tracks) gap
    end.

  (** ** 2. Verification of Gap Allocation & Space Clamping Properties *)

  Lemma num_gaps_zero : num_gaps 0 = 0.
  Proof. reflexivity. Qed.

  Lemma num_gaps_single : num_gaps 1 = 0.
  Proof. reflexivity. Qed.

  Lemma num_gaps_succ : forall n,
    n >= 1 -> num_gaps (S n) = S (num_gaps n).
  Proof.
    intros n H. unfold num_gaps. lia.
  Qed.

  Theorem available_track_space_partition : forall w_total n gap,
    w_total >= total_gap_space n gap ->
    available_track_space w_total n gap + total_gap_space n gap = w_total.
  Proof.
    intros w_total n gap H.
    unfold available_track_space.
    lia.
  Qed.

  Theorem available_track_space_clamped : forall w_total n gap,
    w_total < total_gap_space n gap ->
    available_track_space w_total n gap = 0.
  Proof.
    intros w_total n gap H.
    unfold available_track_space.
    lia.
  Qed.

  (** ** 3. Verification of Offset Advancement Invariants *)

  Lemma compute_track_offsets_length : forall tracks gap init_off,
    length (compute_track_offsets tracks gap init_off) = length tracks.
  Proof.
    induction tracks as [| t ts IH]; intros gap init_off; simpl.
    - reflexivity.
    - f_equal. apply IH.
  Qed.

  (** Closed-form characterization of the i-th track offset. *)
  Theorem track_offset_nth_closed_form : forall tracks gap init_off i,
    i < length tracks ->
    nth i (compute_track_offsets tracks gap init_off) 0 =
    init_off + sum_tracks (firstn i tracks) + i * gap.
  Proof.
    induction tracks as [| t ts IH]; intros gap init_off i Hi.
    - simpl in Hi. lia.
    - destruct i as [| i'].
      + simpl. lia.
      + simpl in Hi. assert (Hi' : i' < length ts) by lia.
        simpl. rewrite IH by exact Hi'.
        lia.
  Qed.

  (** Invariant 3a: Track offsets advance by exactly (track_size + gap). *)
  Theorem track_offset_step_invariant : forall tracks gap init_off i,
    S i < length tracks ->
    nth (S i) (compute_track_offsets tracks gap init_off) 0 =
    nth i (compute_track_offsets tracks gap init_off) 0 + (nth i tracks 0) + gap.
  Proof.
    induction tracks as [| t ts IH]; intros gap init_off i Hi.
    - simpl in Hi. lia.
    - destruct i as [| i'].
      + destruct ts as [| t2 ts'].
        * simpl in Hi. lia.
        * simpl. lia.
      + simpl in Hi. assert (Hi' : S i' < length ts) by lia.
        simpl. apply IH. exact Hi'.
  Qed.

  (** Strict monotonicity when track_size + gap > 0. *)
  Corollary track_offset_strictly_advances : forall tracks gap init_off i,
    S i < length tracks ->
    nth i tracks 0 + gap > 0 ->
    nth i (compute_track_offsets tracks gap init_off) 0 <
    nth (S i) (compute_track_offsets tracks gap init_off) 0.
  Proof.
    intros tracks gap init_off i Hlen Hpos.
    rewrite track_offset_step_invariant by exact Hlen.
    lia.
  Qed.

  (** ** 4. Verification of Total Span Conservation Invariant *)

  Lemma firstn_all_sum : forall (tracks : list nat),
    sum_tracks (firstn (length tracks) tracks) = sum_tracks tracks.
  Proof.
    intros tracks. rewrite firstn_all. reflexivity.
  Qed.

  Lemma sum_tracks_split_last : forall (tracks : list nat) i,
    S i = length tracks ->
    sum_tracks (firstn i tracks) + nth i tracks 0 = sum_tracks tracks.
  Proof.
    induction tracks as [| t ts IH]; intros i Hlen.
    - simpl in Hlen. discriminate.
    - destruct i as [| i'].
      + simpl in Hlen. inversion Hlen as [H0].
        destruct ts; simpl in H0; try discriminate.
        simpl. lia.
      + simpl in Hlen. inversion Hlen as [Hlen'].
        simpl. rewrite <- IH with (i := i') by exact Hlen'.
        lia.
  Qed.

  (** Invariant 3b: The end edge of the last track (offset_{N-1} + size_{N-1})
      relative to init_off equals sum(tracks) + (N - 1) * gap = total_grid_span. *)
  Theorem total_span_conservation_invariant : forall tracks gap init_off,
    tracks <> [] ->
    let n := length tracks in
    let last_idx := n - 1 in
    let last_offset := nth last_idx (compute_track_offsets tracks gap init_off) 0 in
    let last_size := nth last_idx tracks 0 in
    (last_offset + last_size) - init_off = total_grid_span tracks gap.
  Proof.
    intros tracks gap init_off Hnonempty n last_idx last_offset last_size.
    assert (Hn_pos : n > 0).
    { unfold n. destruct tracks; [contradiction | simpl; lia]. }
    assert (Hlast_lt : last_idx < n) by (unfold last_idx; lia).
    unfold last_offset.
    rewrite track_offset_nth_closed_form by exact Hlast_lt.
    assert (Hsum : sum_tracks (firstn last_idx tracks) + last_size = sum_tracks tracks).
    { unfold last_size. apply sum_tracks_split_last. unfold last_idx, n. lia. }
    unfold total_grid_span.
    destruct tracks as [| t ts]; [contradiction |].
    unfold total_gap_space, num_gaps.
    fold n.
    unfold last_idx in *.
    lia.
  Qed.

End BlinkGridGapDistribution.
```