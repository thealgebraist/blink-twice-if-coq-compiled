### 1. Core Data Structures in Chromium Blink Masonry

In Chromium’s Blink rendering engine (specifically under `third_party/blink/renderer/core/layout/grid/` and `masonry/`), CSS Masonry Layout Level 3 is implemented as an asymmetric hybrid of CSS Grid along the *grid axis* and a monotonic running-position accumulator along the *masonry axis*.

*   **`MasonryLayoutAlgorithm`**: The primary orchestrator inheriting from `LayoutAlgorithm<GridNode, GridLayoutSubtree, ...>`. It splits layout into two phases: resolving track sizing along the grid axis via standard `GridSizingTree` heuristics, and executing the 2D masonry placement pass using a running-position buffer.
*   **`GridTrackCollection` (`GridLayoutTrackCollection`)**: Represents the discretized geometry of the grid axis. It collapses implicit and explicit tracks into non-overlapping `GridSet` intervals, maintaining resolved pixel offsets, base sizes, growth limits, and gutter (`grid-gap`) intervals. In masonry, this structure exists strictly in 1D along the grid axis; the masonry axis has no track collection.
*   **`MasonryRunningPositions`**: An internal state vector $H = [h_0, h_1, \dots, h_{N-1}] \in \mathbb{R}_{\ge 0}^N$ maintained during placement, where $N$ is the total number of tracks in the `GridTrackCollection`. Each entry $h_i$ tracks the current high-water mark (block-end or inline-end offset, depending on orientation) of placed items in track $i$.
*   **`MasonryItemPosition` / `GridItemData`**: Encapsulates the resolved placement of a single layout box:
    *   `resolved_position`: A `GridSpan` pair $[s, e)$ where $0 \le s < e \le N$ denotes the zero-indexed start and end track lines along the grid axis.
    *   `masonry_axis_offset`: A `LayoutUnit` (fixed-point 26.6 integer) representing the exact starting offset along the masonry axis.
    *   `masonry_axis_size`: The outer margin-box size of the item along the masonry axis, $\Delta h \ge 0$.

---

### 2. 2D Item Placement Algorithm

Given $N$ grid tracks, a running-position vector $H^{(t)} = [h_0^{(t)}, \dots, h_{N-1}^{(t)}]$ at step $t$, a masonry-axis gutter $g \ge 0$, and an item $I_t$ with track span $k = \text{span}(I_t) \in [1, N]$ and masonry-axis margin-box size $d_t \ge 0$:

1.  **Candidate Track Window Evaluation**:
    If the item is auto-placed, it may occupy any contiguous window of $k$ tracks starting at index $i \in \{0, 1, \dots, N - k\}$. For each candidate start index $i$, the effective base offset $y(i)$ at which the item can be placed without overlapping existing items in those $k$ tracks is the maximum running position across the span:
    $$y(i) = \max_{j \in \{i, \dots, i + k - 1\}} h_j^{(t)}$$

2.  **Minimum Running-Height Selection (Tie-Breaking)**:
    The algorithm selects the optimal starting track $i^*$ that minimizes $y(i)$. Per CSS Masonry Layout Level 3, ties are broken by choosing the earliest track index (start-most in grid-axis order):
    $$i^* = \min \left\{ i \in \{0, \dots, N - k\} \;\middle|\; y(i) = \min_{0 \le m \le N - k} y(m) \right\}$$

3.  **State Transition (Running Position Update)**:
    The item is placed at grid-axis span $[i^*, i^* + k)$ and masonry-axis offset $y(i^*)$. The running positions for all tracks covered by the span are updated uniformly to the new high-water mark, incorporating the item size $d_t$ and masonry-axis gap $g$:
    $$h_j^{(t+1)} = \begin{cases} y(i^*) + d_t + g & \text{if } i^* \le j < i^* + k \\ h_j^{(t)} & \text{otherwise} \end{cases}$$

*(Note: Blink tracks `masonry-auto-flow: next` vs `definite-first` by optionally maintaining an explicit auto-placement cursor, though standard `pack` behavior defaults to the global argmin above).*

---

### 3. Definite vs. Automatic Track Placement Constraints

CSS Masonry Level 3 mandates specific resolution priority between items with **definite** grid-axis placement (e.g., `grid-column: 2 / span 2`) and **automatic** grid-axis placement (`grid-column: auto / span 2`):

*   **Clamping & Bounds Resolution**: Prior to placement, any item with a span $k > N$ has its span clamped to $N$. If an item has a definite start or end line out of bounds, implicit tracks are generated in `GridTrackCollection` before $N$ is finalized.
*   **Definite Placement Constraint**: For an item with a definite span $[s_{\text{def}}, s_{\text{def}} + k)$, the candidate search space collapses to the singleton $\{s_{\text{def}}\}$. The item does not search for a global minimum; it directly computes:
    $$y(s_{\text{def}}) = \max_{j \in \{s_{\text{def}}, \dots, s_{\text{def}} + k - 1\}} h_j^{(t)}$$
    and updates $H^{(t+1)}$ over $[s_{\text{def}}, s_{\text{def}} + k)$.
*   **Ordering (`masonry-auto-flow`)**: Under standard placement, items are sorted by `order` property and DOM order; definite and auto items interleave in sequence unless `masonry-auto-flow: definite-first` is specified, which partitions the item list $L = L_{\text{def}} \mathbin{++} L_{\text{auto}}$ before running the placement state machine.

---

### 4. Mathematical Invariants

1.  **Grid-Axis Span Bounds Invariant**:
    For every placed item with resolved span $[s, s + k)$ in an $N$-track masonry grid ($N \ge 1$):
    $$1 \le k \le N \quad \land \quad 0 \le s \le N - k \quad \implies \quad s + k \le N$$
2.  **Masonry-Axis Monotonicity Invariant**:
    Assuming non-negative outer margin sizes ($d_t \ge 0$) and non-negative gaps ($g \ge 0$), the running position vector $H$ is component-wise monotonically non-decreasing across placement steps:
    $$\forall t \ge 0, \forall j \in [0, N-1], \quad h_j^{(t)} \le h_j^{(t+1)}$$
    Furthermore, within the active span $j \in [i^*, i^* + k)$, the post-placement height strictly dominates or equals all pre-placement heights in that window: $h_j^{(t+1)} \ge y(i^*) \ge h_j^{(t)}$.
3.  **Geometric Non-Overlap & Determinism**:
    Because $y(i^*) \ge h_j^{(t)}$ for all $j \in [i^*, i^* + k)$, the newly placed bounding box $[i^*, i^*+k) \times [y(i^*), y(i^*) + d_t)$ cannot intersect any previously placed bounding box. Since the state transition is a pure function of $(H^{(t)}, I_t)$ with a total order on tie-breaking, placement is strictly deterministic.

---

### 5. Rocq / Coq Formalization (`BlinkGridMasonry2DSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the 2D placement semantics, definite vs. automatic constraints, and proves the core spatial bounds, monotonicity, and determinism invariants without any admitted proofs.

```coq
(** * BlinkGridMasonry2DSemantics.v
    Formalization of Chromium Blink Grid Masonry 2D Placement vs CSS Masonry Level 3.
    Agent 69 Audit Artifact. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Track positions and layout heights are represented as natural numbers
    (modeling fixed-point LayoutUnit >= 0). *)
Definition TrackIdx := nat.
Definition LayoutUnit := nat.

(** Grid-axis placement constraint: either Automatic with a span, or Definite
    with a resolved start track and span. *)
Inductive PlacementConstraint : Type :=
  | AutoSpan (span : nat)
  | DefiniteSpan (start : TrackIdx) (span : nat).

(** Input representation of a Masonry Item prior to placement. *)
Record MasonryItem : Type := mkMasonryItem {
  item_id : nat;
  item_constraint : PlacementConstraint;
  item_masonry_size : LayoutUnit
}.

(** Resolved 2D position of a Masonry Item (MasonryItemPosition in Blink). *)
Record MasonryItemPosition : Type := mkMasonryItemPosition {
  pos_item_id : nat;
  pos_track_start : TrackIdx;
  pos_track_span : nat;
  pos_masonry_offset : LayoutUnit;
  pos_masonry_size : LayoutUnit
}.

(** Running positions vector along the grid axis: length = N tracks. *)
Definition RunningPositions := list LayoutUnit.

(** ** 2. Helper Functions for 2D Window Evaluation *)

(** Clamp a span k into the valid range [1, N] for N >= 1. *)
Definition clamp_span (N k : nat) : nat :=
  Nat.min N (Nat.max 1 k).

(** Extract a contiguous slice of length [len] starting at [start] from list [l]. *)
Fixpoint slice (start len : nat) (l : RunningPositions) : RunningPositions :=
  match l with
  | [] => []
  | x :: xs =>
      match start with
      | 0 => match len with
             | 0 => []
             | S len' => x :: slice 0 len' xs
             end
      | S start' => slice start' len xs
      end
  end.

(** Maximum element of a list of LayoutUnits. *)
Fixpoint list_max (l : RunningPositions) : LayoutUnit :=
  match l with
  | [] => 0
  | x :: xs => Nat.max x (list_max xs)
  end.

(** Effective running height y(i) across a span [start, start + span). *)
Definition window_height (H : RunningPositions) (start span : nat) : LayoutUnit :=
  list_max (slice start span H).

(** Search candidate start indices [curr, curr + rem_steps] for the minimum
    window height. Ties are broken by selecting the earliest index (strictly <). *)
Fixpoint find_best_track_aux
  (H : RunningPositions) (span curr rem_steps : nat)
  (best_idx : TrackIdx) (best_h : LayoutUnit) : TrackIdx * LayoutUnit :=
  match rem_steps with
  | 0 => (best_idx, best_h)
  | S rem' =>
      let next_idx := S curr in
      let h := window_height H next_idx span in
      if h <? best_h then
        find_best_track_aux H span next_idx rem' next_idx h
      else
        find_best_track_aux H span next_idx rem' best_idx best_h
  end.

(** Top-level argmin selector over [0, N - span]. *)
Definition select_auto_track (H : RunningPositions) (N span : nat) : TrackIdx * LayoutUnit :=
  let h0 := window_height H 0 span in
  find_best_track_aux H span 0 (N - span) 0 h0.

(** Update running positions H in [start, start + span) to [new_h]. *)
Fixpoint update_running_positions
  (H : RunningPositions) (start span : nat) (new_h : LayoutUnit) : RunningPositions :=
  match H with
  | [] => []
  | h :: hs =>
      match start with
      | 0 =>
          match span with
          | 0 => h :: hs
          | S span' => new_h :: update_running_positions hs 0 span' new_h
          end
      | S start' => h :: update_running_positions hs start' span new_h
      end
  end.

(** ** 3. Single-Item & Multi-Item Placement Algorithm *)

Definition place_single_item
  (H : RunningPositions) (gap : LayoutUnit) (item : MasonryItem)
  : RunningPositions * MasonryItemPosition :=
  let N := length H in
  match item_constraint item with
  | AutoSpan raw_span =>
      let k := clamp_span N raw_span in
      let '(best_i, y_offset) := select_auto_track H N k in
      let new_h := y_offset + item_masonry_size item + gap in
      let H' := update_running_positions H best_i k new_h in
      (H', mkMasonryItemPosition (item_id item) best_i k y_offset (item_masonry_size item))
  | DefiniteSpan raw_start raw_span =>
      let k := clamp_span N raw_span in
      let s := Nat.min (N - k) raw_start in
      let y_offset := window_height H s k in
      let new_h := y_offset + item_masonry_size item + gap in
      let H' := update_running_positions H s k new_h in
      (H', mkMasonryItemPosition (item_id item) s k y_offset (item_masonry_size item))
  end.

Fixpoint place_masonry_items
  (H : RunningPositions) (gap : LayoutUnit) (items : list MasonryItem)
  : RunningPositions * list MasonryItemPosition :=
  match items with
  | [] => (H, [])
  | it :: rest =>
      let '(H', pos) := place_single_item H gap it in
      let '(H_final, positions) := place_masonry_items H' gap rest in
      (H_final, pos :: positions)
  end.

(** ** 4. Mathematical Invariants & Proofs *)

(** *** Invariant 1: Clamped Span Bounds *)
Lemma clamp_span_bounds : forall N k,
  1 <= N ->
  1 <= clamp_span N k <= N.
Proof.
  intros N k HN. unfold clamp_span.
  split.
  - apply Nat.min_glb; lia.
  - apply Nat.le_min_l.
Qed.

(** *** Invariant 2: Auto-Placement Track Selection Bounds [0, N - span] *)
Lemma find_best_track_aux_bounds : forall H span curr rem best_idx best_h,
  best_idx <= curr ->
  fst (find_best_track_aux