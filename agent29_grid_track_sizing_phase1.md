### 1. Core Data Structures in Blink Grid Track Sizing

In Chromium's LayoutNG (`third_party/blink/renderer/core/layout/grid/`), the CSS Grid track sizing algorithm is decoupled from individual DOM nodes by grouping adjacent tracks with identical sizing definitions into contiguous sets (`GridSet`), reducing outer algorithmic complexity from $O(\text{tracks})$ to $O(\text{sets})$.

#### `GridTrackSizingAlgorithm` (implemented in `GridLayoutAlgorithm`)
The stateless orchestrator that drives the sizing phases defined in CSS Grid 1 §11.4–11.8. Key responsibilities and state dependencies:
*   **`GridSizingTrackCollection`**: Holds the vector of `GridSet`s and `GridRange`s (intervals bounded by item start/end lines that map grid items to the exact `GridSet` subset they span).
*   **`TrackSizingRestriction`**: Enum (`kNoRestriction`, `kForbidIntrinsicMinimums`, etc.) governing how `auto` and intrinsic definitions evaluate under definite vs. indefinite container constraints.
*   **Phase Entrypoints**: `InitializeTrackSizes()`, `ResolveIntrinsicTrackSizes()`, `MaximizeTracks()`, `ExpandFlexibleTracks()`, and `StretchAutoTracks()`.

#### `GridSet`
Represents $N \ge 1$ tracks sharing the same `GridTrackSize` within a single `GridRange` boundary. All calculations inside the algorithm operate on `GridSet`s rather than individual tracks, multiplying single-track contributions by `track_count`.
*   `track_count` ($\mathbb{N}_{>0}$): Number of merged tracks in this set.
*   `track_size` (`GridTrackSize`): The resolved `MinTrackBreadth` and `MaxTrackBreadth` sizing functions.
*   `base_size` (`LayoutUnit`): Current accumulated base size for *all* tracks in this set combined.
*   `growth_limit` (`LayoutUnit`): Current accumulated growth limit for the set (`kIndefiniteSize = -1` represents $\infty$).
*   `incurred_increase` (`LayoutUnit`): Transient scratchpad variable storing the delta planned during a single step of `DistributeExtraSpaceToSets`.
*   `fit_content_limit` (`LayoutUnit`): Upper bound if the set is `fit-content(<length-percentage>)`.
*   `is_infinitely_growable` (`bool`): Flag controlling whether an infinite `growth_limit` can be raised during maximization/intrinsic resolution.

#### `GridTrackSize` & `GridLength`
Represents the CSS track definition `minmax(min, max)`, `auto`, `<flex>`, or `fit-content()`.
*   `min_track_breadth_`: A `GridLength` representing the minimum sizing function (`<length-percentage>`, `min-content`, `max-content`, `auto`).
*   `max_track_breadth_`: A `GridLength` representing the maximum sizing function (`<length-percentage>`, `min-content`, `max-content`, `auto`, `<flex>`).
*   Cached boolean predicates computed on construction: `HasIntrinsicMinTrackBreadth()`, `HasMinOrMaxContentMinTrackBreadth()`, `HasAutoMinTrackBreadth()`, `HasFixedMaxTrackBreadth()`, `HasFlexMaxTrackBreadth()`, etc.

#### `GridItemData`
Encapsulates the layout properties and span mappings of a single grid item:
*   `resolved_position` (`GridSpan`): Start and end track lines in both columns and rows.
*   `range_indices` (`BeginSetIndex`, `EndSetIndex`): Pointers directly into the `GridSizingTrackCollection`'s `GridSet` array, avoiding binary searches during Phase 2 intrinsic sizing.
*   `is_sizing_dependent_on_block_size`: Tracks orthogonal flow dependencies.
*   **Contribution Caches**: Methods/fields yielding `MinContentContribution`, `MaxContentContribution`, and `MinSizeContribution` (the clamped automatic minimum size).

---

### 2. Track Initialization (CSS Grid 1 §11.5.1)

In Blink, `GridSizingTrackCollection::InitializeSets` implements CSS Grid 1 §11.5 "Initialize Track Sizes". For each `GridSet` with track count $C$ and container available size $S_{\text{avail}}$:

#### Resolving `base_size`
1.  **Fixed Min Breadth (`<length-percentage>`)**:
    *   If the `<length-percentage>` is definite (either a fixed `<length>`, or a `<percentage>` when $S_{\text{avail}}$ is definite):
        $$\text{base\_size} = \max(0, \text{ResolveLengthPercentage}(\text{min\_breadth}, S_{\text{avail}})) \times C$$
    *   If it is an unresolvable `<percentage>` ($S_{\text{avail}}$ is indefinite), the min breadth falls back to `auto`, which evaluates as an intrinsic minimum:
        $$\text{base\_size} = 0$$
2.  **Intrinsic Min Breadth (`min-content`, `max-content`, `auto`, `fit-content`)**:
    $$\text{base\_size} = 0$$

#### Resolving `growth_limit`
1.  **Fixed Max Breadth (`<length-percentage>`)**:
    *   If definite:
        $$\text{raw\_limit} = \max(0, \text{ResolveLengthPercentage}(\text{max\_breadth}, S_{\text{avail}})) \times C$$
        To immediately uphold the fundamental invariant ($\text{base\_size} \le \text{growth\_limit}$), Blink clamps it:
        $$\text{growth\_limit} = \max(\text{base\_size}, \text{raw\_limit})$$
    *   If it is an unresolvable `<percentage>`, the max breadth falls back to `auto` ($\infty$).
2.  **Intrinsic or Flexible Max Breadth (`min-content`, `max-content`, `auto`, `<flex>`, `fit-content`)**:
    $$\text{growth\_limit} = \infty \quad (\text{represented as } \texttt{kIndefiniteSize} = -1)$$

*Note on `fit-content(L)`*: It initializes with $\text{base\_size} = 0$ and $\text{growth\_limit} = \infty$, while recording $\text{fit\_content\_limit} = \text{Resolve}(L) \times C$ to clamp growth during distribution.

---

### 3. Distributing Intrinsic Size Across Spanned Tracks (§11.5.2 – §11.5.4)

Phase 2 of intrinsic sizing (`ResolveIntrinsicTrackSizes`) processes items grouped by their span length $k = 1, 2, \dots, K$. Within each span group, it executes five sub-steps:
1.  **Step 1**: Intrinsic minimums (`min-content`, `auto` under certain constraints) $\to$ `base_size`.
2.  **Step 2**: Content-based minimums (`min-content`, `max-content`) $\to$ `base_size`.
3.  **Step 3**: Max-content minimums (`max-content`) $\to$ `base_size`.
4.  **Step 4**: Intrinsic maximums (`min-content`, `auto`, `fit-content`) $\to$ `growth_limit`.
5.  **Step 5**: Max-content maximums (`max-content`, `auto`, `fit-content`) $\to$ `growth_limit`.

#### The Distribution Algorithm (`DistributeExtraSpaceToSets`)
When an item $i$ spanning a sequence of `GridSet`s $\mathcal{S}_i$ has a size contribution $M_i$ (e.g., its `MinContentContribution` minus any grid gaps it spans), the extra space to distribute is:
$$\Delta_i = \max\left(0, M_i - \sum_{s \in \mathcal{S}_i} s.\text{base\_size}\right)$$

If $\Delta_i > 0$, Blink filters $\mathcal{S}_i$ to the subset of sets $\mathcal{T}_i \subseteq \mathcal{S}_i$ that have a qualifying intrinsic min track sizing function for the current sub-step. For each $s \in \mathcal{T}_i$, its `incurred_increase` is initialized to $0$.

The distribution of $\Delta_i$ across $\mathcal{T}_i$ occurs in two passes to respect `growth_limit`s:

##### Pass 1: Constrained Growth (Up to `growth_limit`)
All sets in $\mathcal{T}_i$ are sorted by their **growth potential** per track. For a set $s$ modifying its `base_size`:
$$\text{potential}(s) = \begin{cases} \infty & \text{if } s.\text{growth\_limit} = \infty \\ \max(0, s.\text{growth\_limit} - s.\text{base\_size}) & \text{otherwise} \end{cases}$$

Blink iterates through the sets in $\mathcal{T}_i$ to distribute $\Delta_i$ **equally per individual track**, capping each set's `incurred_increase` at its $\text{potential}(s)$. Specifically, if $R$ tracks remain eligible across the remaining un-maxed sets in $\mathcal{T}_i$, a candidate set $s$ receives:
$$\text{share}(s) = \min\left(\text{potential}(s), \Delta_{\text{rem}} \times \frac{s.\text{track\_count}}{R}\right)$$
*(In fixed-point `LayoutUnit` arithmetic, Blink orders sets by $\frac{\text{potential}(s)}{s.\text{track\_count}}$ ascending so that the tightest cap is hit first, subtracts the capped amount from $\Delta_{\text{rem}}$, removes $s.\text{track\_count}$ from $R$, and repeats).*

##### Pass 2: Unconstrained Growth (Beyond `growth_limit`)
If $\Delta_{\text{rem}} > 0$ after all $s \in \mathcal{T}_i$ have reached their `growth_limit` (which only happens if all $s \in \mathcal{T}_i$ had finite `growth_limit`s), CSS Grid §11.5.5 mandates distributing the remaining space across a fallback subset $\mathcal{T}^*_i \subseteq \mathcal{T}_i$:
*   If any set in $\mathcal{T}_i$ has a `max-content` max-breadth (or an intrinsic max-breadth that wasn't fixed), filter to those; otherwise use all of $\mathcal{T}_i$.
*   Distribute $\Delta_{\text{rem}}$ proportionally by `track_count` across $\mathcal{T}^*_i$ (still respecting `fit-content` limits if applicable).

##### Batching Commit (Order Independence within Span Group)
Crucially, during a single sub-step for span length $k$, items do **not** immediately mutate `s.base_size`. Instead, each item $i$ computes `s.incurred_increase` for its spanned sets, and updates a high-water mark on the set:
$$s.\text{planned\_increase} = \max_{i} (s.\text{incurred\_increase}_i)$$
At the end of the sub-step for span $k$, Blink commits the increases and enforces the growth limit invariant:
$$s.\text{base\_size} \gets s.\text{base\_size} + s.\text{planned\_increase}$$
$$\text{if } s.\text{growth\_limit} \neq \infty \land s.\text{growth\_limit} < s.\text{base\_size} \implies s.\text{growth\_limit} \gets s.\text{base\_size}$$

---

### 4. Mathematical Invariants

1.  **Well-Formedness (Base-Limit Ordering)**:
    At initialization and at the conclusion of every sub-step:
    $$\forall s \in \text{Sets},\quad s.\text{growth\_limit} = \infty \;\lor\; 0 \le s.\text{base\_size} \le s.\text{growth\_limit}$$
2.  **Monotonicity of Base Size and Finite Growth Limits**:
    Across any Phase 1 or Phase 2 transition $s \to s'$:
    $$s.\text{base\_size} \le s'.\text{base\_size}$$
    $$\forall L \in \mathbb{N},\; s.\text{growth\_limit} = L \implies \exists L' \in \mathbb{N},\; s'.\text{growth\_limit} = L' \land L \le L'$$
3.  **Exact Space Conservation (Per Item Pass)**:
    For a single item distribution pass with target subset $\mathcal{T}_i \neq \emptyset$ and extra space $\Delta_i \ge 0$ (assuming no `fit-content` clamps):
    $$\sum_{s \in \mathcal{T}_i} s.\text{incurred\_increase} = \Delta_i$$
    Consequently, after committing $s.\text{planned\_increase} \ge s.\text{incurred\_increase}_i$:
    $$\sum_{s \in \mathcal{S}_i} s'.\text{base\_size} \ge M_i$$

---

### 5. Rocq / Coq Formalization (`BlinkGridTrackPhase1Semantics.v`)

The following script is fully self-contained and compiles cleanly in Coq/Rocq (8.16+ / 9.0) using standard `Arith` and `Lia` libraries.

```coq
(** * BlinkGridTrackPhase1Semantics.v
    Formalization of Chromium Blink's CSS Grid Track Sizing Phase 1 (Initialization)
    and Phase 2 (Intrinsic Track Size Resolution - Base Size Distribution)
    against CSS Grid Layout Module Level 1 §11.5. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Growth limits can be a finite non-negative LayoutUnit (modeled as [nat])
    or indefinite/infinite ([kIndefiniteSize] in Blink). *)
Inductive GrowthLimit : Type :=
  | GL_Finite (n : nat)
  | GL_Infinite.

(** CSS Grid Track Breadth sizing functions.
    Percentage resolution is modeled as pre-resolved to either [Fixed] (when container
    is definite) or degraded to [Auto] / [MaxContent] (when container is indefinite). *)
Inductive MinTrackBreadth : Type :=
  | Min_Fixed (len : nat)
  | Min_Auto
  | Min_MinContent
  | Min_MaxContent.

Inductive MaxTrackBreadth : Type :=
  | Max_Fixed (len : nat)
  | Max_Auto
  | Max_MinContent
  | Max_MaxContent
  | Max_Flex (fr : nat).

Record GridTrackSize : Type := mkGridTrackSize {
  min_breadth : MinTrackBreadth;
  max_breadth : MaxTrackBreadth
}.

(** A [GridSet] represents [track_count] adjacent tracks with identical [GridTrackSize].
    Sizes are stored as the sum over all tracks in the set, matching Blink's LayoutNG. *)
Record GridSet : Type := mkGridSet {
  track_count : nat;
  track_size  : GridTrackSize;
  base_size   : nat;
  growth_limit: GrowthLimit;
  planned_inc : nat
}.

(** A [GridItemData] in Phase 2 is characterized by