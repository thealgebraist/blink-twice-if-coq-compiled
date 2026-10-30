### 1. Core Data Structures in Blink Grid Track Sizing

In Chromium's LayoutNG (`third_party/blink/renderer/core/layout/grid/`), the CSS Grid track sizing algorithm (CSS Grid Layout Module Level 1, §11) is optimized by collapsing adjacent or identically-behaving tracks into contiguous ranges called **Sets**. This reduces the complexity of the track sizing algorithm from $O(N_{\text{tracks}} \times N_{\text{items}})$ to $O(N_{\text{sets}} \times N_{\text{items}})$.

```
GridSizingTrackCollection
 ├── Vector<GridTrack> (Raw explicit/implicit tracks)
 └── Vector<GridSet>   (Deduplicated track groupings)
       ├── track_count (Number of tracks in this set)
       ├── base_size   (LayoutUnit: current resolved size)
       ├── growth_limit(LayoutUnit: maximum limit, can be kIndefiniteSize)
       └── track_size  (GridTrackSize: min/max sizing functions)
```

#### `GridTrackSize` (`grid_track_size.h`)
Represents the parsed CSS track definition (e.g., `minmax(100px, 1fr)`, `auto`, `fit-content(200px)`).
*   **Min Track Sizing Function (`min_track_breadth_`)**: `Length` (`kFixed`, `kMinContent`, `kMaxContent`, `kAuto`).
*   **Max Track Sizing Function (`max_track_breadth_`)**: `Length` (`kFixed`, `kMinContent`, `kMaxContent`, `kAuto`, `kFlex`).
*   **Cached Booleans**: Bitfields caching properties like `has_intrinsic_min_track_breadth_`, `has_flex_max_track_breadth_`, `is_content_sized_`, etc., to avoid branching during the hot loops in §11.5–11.7.

#### `GridSet` (`grid_track_collection.h`)
A `GridSet` represents a group of $k$ tracks (`track_count`) that share identical `GridTrackSize` definitions and are spanned identically by every grid item intersecting them.
*   **`track_count` (`wtf_size_t`)**: Number of individual grid tracks combined into this set.
*   **`track_size` (`GridTrackSize`)**: The unified sizing rules for all tracks in this set.
*   **`base_size` (`LayoutUnit`)**: The cumulative base size of **all** tracks in this set. Invariant: `base_size >= 0`.
*   **`growth_limit` (`LayoutUnit`)**: The cumulative growth limit of all tracks in this set. Represented as `kIndefiniteSize` (`LayoutUnit(-1)`) when unbounded ($\infty$). Invariant: If `growth_limit != kIndefiniteSize`, then `growth_limit >= base_size`.
*   **`fit_content_limit` (`LayoutUnit`)**: Cap used when the track is `fit-content(<length>)`.
*   **`incurred_increase` (`LayoutUnit`)**: Temporary accumulator used during §11.5 (Resolve Intrinsic Track Sizes) and §11.6 (Maximize Tracks) to stage increases before committing them to `base_size` or `growth_limit`.

#### `GridSizingTrackCollection` (`grid_track_collection.h`)
Inherits from `GridLayoutTrackCollection`. It manages the lifecycle of `GridSet`s and maps grid item spans to specific subsets of `GridSet`s.
*   **`sets_` (`Vector<GridSet>`)**: The contiguous array of sets for a given dimension (`kForColumns` or `kForRows`).
*   **`ranges_` (`Vector<Range>`)**: Divides the grid lines into segments where no grid item starts or ends mid-range. Each `Range` points to a slice of `sets_`.

#### `GridItemData` (`grid_item.h`)
Represents a single child element placed within the grid.
*   **`SetIndices` (`Begin` and `End`)**: Cached indices into the `GridSizingTrackCollection::sets_` vector for both columns and rows. This allows $O(1)$ lookup of the exact `GridSet` slice a grid item spans.
*   **`SpanSize`**: The number of tracks spanned.

---

### 2. Growth Algorithm: `DistributeExtraSpaceToSets`

CSS Grid 1 §11.5 ("Resolve Intrinsic Track Sizes") and §11.6 ("Maximize Tracks") both rely on a single foundational primitive in Blink: **`DistributeExtraSpaceToSets`** (located in `grid_layout_algorithm.cc`). 

When maximizing tracks (§11.6), the algorithm takes the available **free space** (Grid Container inner size minus the sum of all sets' `base_size`s and grid gaps) and distributes it to sets to grow their `base_size` up to their `growth_limit`.

#### Step-by-Step Execution in Blink

1.  **Initialization**:
    Let $S$ be the list of `GridSet`s participating in the distribution (`sets_to_grow`). For each set $s_i \in S$, `s_i.incurred_increase = 0`.
    Let `extra_space` ($\Delta_{\text{free}}$) be the positive `LayoutUnit` of space to distribute.

2.  **Partitioning / Filtering Growable Sets**:
    A set $s_i$ is considered *growable* if its `growth_limit` is strictly greater than its current `base_size` (or if its `growth_limit` is `kIndefiniteSize`).
    Let $G \subseteq S$ be the subset of currently unfrozen, growable sets.

3.  **Iterative Distribution Loop**:
    While $\Delta_{\text{free}} > 0$ and $G \neq \emptyset$:
    *   **Compute Total Weight ($W$)**:
        In standard distribution (`MaximizeTracks` and intrinsic base size resolution), the weight of a set is its `track_count`. (In `stretch` distribution §11.8, weight is `flex_factor` or track count).
        $$W = \sum_{s_i \in G} \text{weight}(s_i)$$
    *   **Sort or Scan for Freeze Candidates**:
        To ensure every single track in $G$ receives an equal share of space *unless* capped by its `growth_limit`, Blink calculates a tentative per-unit share:
        $$\text{share}(s_i) = \Delta_{\text{free}} \times \frac{\text{weight}(s_i)}{W}$$
    *   **Check Growth Potential (`GrowthPotentialForSet`)**:
        For each $s_i \in G$, define its remaining headroom (growth potential) as:
        $$\text{potential}(s_i) = \begin{cases} \infty & \text{if } \text{limit}(s_i) = \text{kIndefiniteSize} \\ \text{limit}(s_i) - \text{base}(s_i) - \text{incurred}(s_i) & \text{otherwise} \end{cases}$$
        *(Note: If the track is `fit-content(L)`, $\text{potential}(s_i)$ is additionally capped at $\max(0, L - \text{base}(s_i) - \text{incurred}(s_i))$).*
    *   **Freeze Pass**:
        If there exists any $s_i \in G$ where $\text{potential}(s_i) \le \text{share}(s_i)$, that set cannot absorb its full proportional share. 
        Blink identifies sets that reach their limit first (i.e., those with the smallest $\frac{\text{potential}(s_i)}{\text{weight}(s_i)}$ ratio). For these sets:
        $$\text{incurred}(s_i) \gets \text{incurred}(s_i) + \text{potential}(s_i)$$
        $$\Delta_{\text{free}} \gets \Delta_{\text{free}} - \text{potential}(s_i)$$
        $$G \gets G \setminus \{s_i\} \quad (\text{Set is frozen})$$
        If any set was frozen in this pass, the loop restarts with the updated $\Delta_{\text{free}}$ and smaller $G$.
    *   **Unconstrained Final Pass**:
        If for all $s_i \in G$, $\text{potential}(s_i) > \text{share}(s_i)$, no set will hit its limit during the remainder of the distribution. Each remaining set receives its exact proportional share:
        $$\text{incurred}(s_i) \gets \text{incurred}(s_i) + \text{share}(s_i)$$
        $$\Delta_{\text{free}} \gets 0$$
        The loop terminates.

4.  **Commit Phase**:
    For all $s_i \in S$:
    $$\text{base}(s_i) \gets \text{base}(s_i) + \text{incurred}(s_i)$$

---

### 3. Free Space Weights, Infinite Limits, and Freeze Conditions

#### Distribution Weights and Fixed-Point Discretization
Blink uses `LayoutUnit` (a 32-bit signed integer representing $\frac{1}{64}$th of a CSS pixel). Because integer division truncates, distributing $\Delta_{\text{free}}$ across $W$ tracks via $\lfloor \Delta_{\text{free}} / W \rfloor$ leaves a remainder $R = \Delta_{\text{free}} \pmod W$ of up to $W - 1$ subpixels (`LayoutUnit::FromRawValue(1)`).

In Blink's `DistributeExtraSpaceToSets`, instead of computing a global $\Delta_{\text{free}} / W$ and losing the remainder, Blink iterates through the active sets $s_1, s_2, \dots, s_k \in G$, maintaining a running `extra_space` and running `growable_track_count`:
```cpp
// Conceptual representation of Blink's exact integer distribution loop:
for (GridSet* set : growable_sets) {
  LayoutUnit share = extra_space * set->TrackCount() / growable_track_count;
  extra_space -= share;
  growable_track_count -= set->TrackCount();
  ...
}
```
This sequential update guarantees that **100% of `extra_space` is distributed** without subpixel leakage, provided at least one set remains unfrozen.

#### Infinite Max Track Handling (`kIndefiniteSize`)
A `GridSet` has `growth_limit == kIndefiniteSize` (`-1`) if its max track sizing function is `max-content`, `auto`, or a `<flex>` value (during §11.5), and no item spanning it has forced a definite limit yet, OR during §11.6 (`MaximizeTracks`) when growing tracks with an unbounded `growth_limit` (though CSS Grid §11.6 states that if free space is indefinite, tracks aren't maximized; if free space is *definite* and a track's growth limit is *infinite*, the track can grow without bound to absorb the definite free space).

In `GrowthPotentialForSet`:
*   When `growth_limit == kIndefiniteSize`, Blink returns `LayoutUnit::Max()` (unless constrained by `fit-content`).
*   Consequently, the condition $\text{potential}(s_i) \le \text{share}(s_i)$ evaluates to `false` (since $\Delta_{\text{free}} < \text{LayoutUnit::Max()}$).
*   Thus, a set with an infinite growth limit **never freezes**. If $G$ contains at least one set with an infinite growth limit (and not capped by `fit-content`), the algorithm is guaranteed to consume the entirety of $\Delta_{\text{free}}$ ($\Delta_{\text{free}}' = 0$).

#### Freeze Conditions
A set $s_i$ transitions from *growable* ($s_i \in G$) to *frozen* ($s_i \notin G$) under two conditions:
1.  **Pre-condition Freeze**: Before distribution begins, $\text{potential}(s_i) = 0$ (i.e., `base_size == growth_limit`).
2.  **Saturation Freeze**: During distribution, the set's proportional share of the remaining `extra_space` meets or exceeds its remaining $\text{potential}(s_i)$. Its `incurred_increase` is clamped to its total initial potential ($\text{limit}(s_i) - \text{base}(s_i)$), and its weight (`track_count`) is removed from $W$.

If **all** sets in $S$ freeze before $\Delta_{\text{free}}$ reaches $0$, the loop terminates because $G = \emptyset$. The leftover space remains unallocated in §11.6 (to be handled later by §11.7 Expand Flexible Tracks or `align-content`/`justify-content` alignment).

---

### 4. Mathematical Invariants

Let $S = \{s_1, \dots, s_n\}$ be the collection of `GridSet`s. For each $s_i$:
*   $b_i \in \mathbb{N}$ is the initial `base_size`.
*   $b'_i \in \mathbb{N}$ is the final `base_size` after distribution.
*   $L_i \in \mathbb{N} \cup \{\infty\}$ is the `growth_limit` (with precondition $L_i \neq \infty \implies b_i \le L_i$).
*   $w_i \in \mathbb{N}^+$ is the `track_count` ($w_i \ge 1$).
*   $\Delta_{\text{free}} \in \mathbb{N}$ is the initial available free space.
*   $\delta_i = b'_i - b_i$ is the `incurred_increase` for set $s_i$.

#### Invariant 1: Monotonic Track Growth
No track set can shrink during free space distribution.
$$\forall i \in \{1, \dots, n\}, \quad b'_i \ge b_i \quad (\text{i.e., } \delta_i \ge 0)$$

#### Invariant 2: Growth Limit Boundedness
If a track set has a definite growth limit, its final base size never exceeds that limit.
$$\forall i \in \{1, \dots, n\}, \quad L_i \neq \infty \implies b'_i \le L_i$$

#### Invariant 3: Space Conservation
The sum of all increases across all sets never exceeds the initial available free space.
$$\sum_{i=1}^{n} \delta_i \le \Delta_{\text{free}}$$

#### Invariant 4: Work Conservation (Exact Exhaustion vs. Total Saturation)
The algorithm does not leave free space unallocated unless every single set has reached its growth limit.
$$\left( \sum_{i=1}^{n} \delta_i = \Delta_{\text{free}} \right) \lor \left( \forall i \in \{1, \dots, n\}, \; L_i \neq \infty \land b'_i = L_i \right)$$
*(Corollary: If $\exists i$ such that $L_i = \infty$, then $\sum_{i=1}^n \delta_i = \Delta_{\text{free}}$).*

---

### 5. Formal Verification in Rocq/Coq (`BlinkGridTrackGrowthSemantics.v`)

Below is a complete, self-