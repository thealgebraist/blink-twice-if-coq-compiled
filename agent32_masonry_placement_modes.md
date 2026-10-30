### 1. Core Data Structures in Blink Masonry Placement

In Chromium's Blink rendering engine (LayoutNG), CSS Masonry Layout Level 1 placement semantics are governed by the state machine tracking the running block-axis positions across the grid-axis tracks.

#### `MasonryAutoFlow`
Blink represents the `masonry-auto-flow` CSS property through two orthogonal execution modifiers:
*   **Placement Algorithm (`MasonryPlacementAlgorithm`)**:
    *   `kPack`: Corresponds to `masonry-auto-flow: pack`. Places the item into the track(s) with the minimum current running position.
    *   `kNext`: Corresponds to `masonry-auto-flow: next`. Places the item into the track immediately at or following the current auto-placement cursor, advancing the cursor post-placement.
*   **Definite Track Handling (`MasonryDefinitePlacement`)**:
    *   `kDefiniteFirst`: corresponds to the default behavior where items with definite grid-axis track positions are placed prior to auto-placed items (or processed in order while prioritizing definite coordinates).
    *   `kOrdered`: corresponds to `masonry-auto-flow: ... ordered`, where items are placed strictly in document order (modulated by `order`), regardless of whether their grid-axis placement is definite or automatic (`auto`).

#### `MasonryPlacementState`
The mutable context updated during the iterative placement of `MasonryItem` instances:
*   `running_positions: Vector<LayoutUnit>`: An array of length $N$ (`track_count`), initialized to $0$. Index $i \in [0, N)$ stores the furthest block-axis margin-box end edge of any item placed in track $i$, plus any applicable masonry-axis `gap` after the item.
*   `auto_placement_cursor: wtf_size_t`: An integer index in $[0, N)$ representing the starting track candidate for the next auto-placed item. Under `kPack`, this acts as a lower-bound scan start if ties occur or resets to $0$; under `kNext`, it tracks the sequential round-robin progression across tracks.
*   `track_count: wtf_size_t`: Total number of explicit and implicit grid-axis tracks ($N \ge 1$).

#### `MasonryItem` & `MasonryPlacedItem`
*   **Input (`MasonryItem`)**:
    *   `span: wtf_size_t`: The number of contiguous tracks the item spans ($1 \le \text{span} \le N$). Clamped to $N$ during track resolution if overspecified.
    *   `definite_track: std::optional<wtf_size_t>`: If present, a resolved starting track index $k \in [0, N - \text{span}]$.
    *   `size: LayoutUnit`: The block-axis outer size (margin box) of the item, plus the masonry-axis track gap.
*   **Output (`MasonryPlacedItem`)**:
    *   `start_track: wtf_size_t`: Resolved grid-axis starting track $k$.
    *   `end_track: wtf_size_t`: $k + \text{span}$.
    *   `block_offset: LayoutUnit`: The resolved starting position along the masonry axis.

---

### 2. Placement Strategies

Let $N$ be the total number of tracks, $R[i]$ for $0 \le i < N$ be the current running position of track $i$, $S$ be the item's track span ($1 \le S \le N$), $H \ge 0$ be the item's block-axis contribution (size + gap), and $c \in [0, N)$ be the current `auto_placement_cursor`.

#### Definite Track Placement (`DefiniteTrack`)
When an item specifies a definite starting track $k$ (where $k + S \le N$):
1.  The placement track is fixed at $k$.
2.  The item's block-axis starting offset is the maximum running position across the spanned tracks:
    $$y = \max_{j \in [k, k+S)} R[j]$$
3.  State update: For all $j \in [k, k+S)$, $R'[j] = y + H$.
4.  Cursor update: Per CSS Masonry Level 1, definite placement advances the auto-placement cursor to $(k + S) \bmod N$.

#### Pack Strategy (`MasonryAutoFlow::kPack`)
For an auto-placed item, `pack` searches all valid starting track indices $k \in [0, N - S]$ to find the contiguous span that minimizes the resulting starting block offset:
1.  For each candidate start track $k \in [0, N - S]$, compute the effective span baseline:
    $$B(k) = \max_{j \in [k, k+S)} R[j]$$
2.  Select the smallest index $k^*$ that minimizes $B(k)$:
    $$k^* = \min \left\{ k \in [0, N - S] \;\middle|\; \forall m \in [0, N - S],\, B(k) \le B(m) \right\}$$
3.  The item is placed at `start_track` $= k^*$ with `block_offset` $y = B(k^*)$.
4.  State update: For all $j \in [k^*, k^*+S)$, $R'[j] = y + H$.
5.  Cursor update: $c' = (k^* + S) \bmod N$.

#### Next Strategy (`MasonryAutoFlow::kNext`)
For an auto-placed item under `next`, placement is driven directly by the `auto_placement_cursor` $c$ without scanning for global height minima:
1.  If the current cursor $c$ cannot accommodate the span ($c + S > N$), the cursor wraps to track $0$:
    $$k^* = \begin{cases} c & \text{if } c + S \le N \\ 0 & \text{if } c + S > N \end{cases}$$
2.  The item's block offset is evaluated at $k^*$:
    $$y = \max_{j \in [k^*, k^*+S)} R[j]$$
3.  State update: For all $j \in [k^*, k^*+S)$, $R'[j] = y + H$.
4.  Cursor update: The cursor advances past the newly placed item and wraps modulo $N$:
    $$c' = (k^* + S) \bmod N$$

---

### 3. Multi-Track Span Placement

When an item spans $S > 1$ tracks, it acts as a horizontal barrier across tracks $[k, k+S)$. 

1.  **Valid Candidate Domain**: An item of span $S$ cannot overhang the explicit/implicit grid. Blink clamps $S \leftarrow \min(S, N)$ prior to placement. Consequently, the valid starting track indices form the closed interval $[0, N - S]$. Because $1 \le S \le N$, this interval is guaranteed to be non-empty (at least track $0$ is always valid).
2.  **Min-Max Running Position Optimization (`pack`)**:
    To prevent overlaps with previously placed items in any of the spanned tracks, the item's top edge must clear the lowest-hanging item across all tracks in the span. Thus, the clearance height for candidate $k$ is $B(k) = \max_{j=k}^{k+S-1} R[j]$. The `pack` mode minimizes this clearance height over the candidate domain:
    $$y_{\text{pack}} = \min_{0 \le k \le N - S} \left( \max_{k \le j < k + S} R[j] \right)$$
    Ties in $B(k)$ are broken deterministically in favor of the start-most track (minimum $k$).
3.  **Running Position Synchronization**:
    Once placed at track $k^*$ at block offset $y = B(k^*)$, the item occupies the vertical interval $[y, y + H)$ across all tracks $j \in [k^*, k^* + S)$. Every track in this span has its running position synchronized to the exact same value $y + H$, flattening local variance across $[k^*, k^* + S)$.

---

### 4. Mathematical Invariants

For any valid transition $(R, c) \xrightarrow{\text{item}(S, H)} (R', c', k^*, y)$ where $N \ge 1$, $1 \le S \le N$, and $H \ge 0$:

1.  **Track Bounds Invariant**: The placed track span lies strictly within the defined tracks:
    $$0 \le k^* \quad \land \quad k^* + S \le N \quad \text{(which implies } k^* < N\text{)}$$
2.  **Cursor Bounds Invariant**: If $c < N$, then after placement, $0 \le c' < N$.
3.  **Clearance Invariant (Placed Position $\ge$ Running Track Height)**: The placed item's block offset $y$ is greater than or equal to the pre-placement running position of every track it spans:
    $$\forall j \in [k^*, k^* + S),\quad y \ge R[j]$$
4.  **Monotonicity & Non-Negativity of Running Heights**: Assuming $\forall i, R[i] \ge 0$ and $H \ge 0$:
    *   Running heights are non-decreasing: $\forall i \in [0, N), R'[i] \ge R[i]$.
    *   Running heights and placed offsets are non-negative: $y \ge 0$ and $\forall i \in [0, N), R'[i] \ge 0$.
5.  **Frame Invariant**: Tracks outside the placed span retain their exact running positions:
    $$\forall i \notin [k^*, k^* + S),\quad R'[i] = R[i]$$
6.  **Pack Optimality Invariant**: Under `kPack` with automatic placement, no valid contiguous span of length $S$ has a strictly smaller maximum running height than $y$:
    $$\forall k \in [0, N - S],\quad y \le \max_{j \in [k, k+S)} R[j]$$
7.  **Determinism**: Placement is a total, pure function of $(R, c, \text{mode}, \text{item})$, yielding a unique state $(R', c')$ and placement $(k^*, y)$.

---

### 5. Rocq / Coq Formalization (`BlinkMasonryPlacementSemantics.v`)

The following formalization is self-contained and compiles cleanly in Rocq / Coq (using standard library `Arith`, `List`, and `Lia`).

```coq
(** * BlinkMasonryPlacementSemantics.v
    Formalization of Chromium Blink CSS Masonry Layout Level 1 Placement Modes. *)

From Coq Require Import Arith List Lia Bool.
Import ListNotations.

Section MasonryPlacement.

(** ** 1. Core Data Structures *)

(** Placement strategies corresponding to Blink's MasonryAutoFlow. *)
Inductive MasonryAutoFlow : Type :=
  | FlowPack : MasonryAutoFlow
  | FlowNext : MasonryAutoFlow.

(** Track placement specification for an individual masonry item. *)
Inductive TrackSpec : Type :=
  | AutoTrack     : TrackSpec
  | DefiniteTrack : nat -> TrackSpec.

(** A Masonry item to be placed.
    [item_span] is encoded via [span_minus_one] to structurally guarantee span >= 1,
    or kept as [nat] with an explicit clamping operation matching Blink's track resolver. *)
Record MasonryItem : Type := mkItem {
  item_spec : TrackSpec;
  item_span : nat; (* Raw span; clamped to [1, track_count] during placement *)
  item_size : nat  (* Block-axis outer size + gap (non-negative in nat) *)
}.

(** Mutable state maintained across item placements. *)
Record MasonryPlacementState : Type := mkState {
  running_positions     : list nat;
  auto_placement_cursor : nat
}.

(** Resolved coordinates for a placed item. *)
Record PlacedItem : Type := mkPlaced {
  placed_track  : nat;
  placed_span   : nat;
  placed_offset : nat
}.

(** Track count is the length of the running_positions vector. *)
Definition track_count (st : MasonryPlacementState) : nat :=
  length (running_positions st).

(** Clamp span S into the valid interval [1, N]. *)
Definition clamp_span (S N : nat) : nat :=
  Nat.min (Nat.max 1 S) N.

(** ** 2. Span Operations & Running Position Updates *)

(** Maximum running position across a contiguous slice [start, start + span). *)
Fixpoint max_in_span (R : list nat) (start span : nat) : nat :=
  match span with
  | 0 => 0
  | S span' =>
      Nat.max (nth start R 0) (max_in_span R (S start) span')
  end.

(** Update tracks in [start, start + span) to [new_val], preserving others. *)
Fixpoint update_span (R : list nat) (start span new_val : nat) : list nat :=
  match R with
  | [] => []
  | h :: t =>
      match start with
      | 0 =>
          match span with
          | 0 => h :: t
          | S span' => new_val :: update_span t 0 span' new_val
          end
      | S start' => h :: update_span t start' span new_val
      end
  end.

(** ** 3. Placement Strategies (Pack, Next, Definite) *)

(** Find the track index k in [cur, cur + rem] that minimizes [max_in_span R k span].
    Ties are broken in favor of the smallest index (first encountered). *)
Fixpoint find_pack_track_aux (R : list nat) (span cur rem best_k best_val : nat) : nat :=
  let cur_val := max_in_span R cur span in
  let (next_k, next_val) :=
    if cur_val <? best_val then (cur, cur_val) else (best_k, best_val)
  in
  match rem with
  | 0 => next_k
  | S rem' => find_pack_track_aux R span (S cur) rem' next_k next_val
  end.

(** Entry point for 'pack' search over k in [0, N - span]. *)
Definition find_pack_track (R : list nat) (span : nat) : nat :=
  let N := length R in
  let max_k := N - span in
  let init_val := max_in_span R 0 span in
  match max_k with
  | 0 => 0
  | S rem => find_pack_track_aux R span 1 rem 0 init_val
  end.

(** Entry point for 'next' track selection given cursor c and span. *)
Definition find_next_track (N cursor span : nat) : nat :=
  if cursor + span <=? N then cursor else 0.

(** Resolve the starting track k* for a given item, flow mode, and state. *)
Definition resolve_start