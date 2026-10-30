# Agent 2 Audit Report: Chromium Blink CSS Subgrid Layout vs. W3C CSS Grid Layout Module Level 2

---

## 1. Core Data Structures in Blink Subgrid

In Chromium’s LayoutNG architecture (specifically within `third_party/blink/renderer/core/layout/grid/`), CSS Grid Level 2 subgrid layout is implemented by flattening nested subgrid hierarchies into the root ancestor grid's track sizing context. Below is the structural breakdown of the four core primitives used by Blink.

### 1.1 `GridSubtree` & `GridSizingTree`
To avoid deep pointer-chasing across `LayoutObject` nodes during the multi-pass Track Sizing Algorithm, Blink linearizes the hierarchy of a root grid and all its nested subgrids into a contiguous array within `GridSizingTree` (`grid_subtree.h` / `grid_sizing_tree.h`).

```cpp
// Conceptual layout of Blink's GridSizingTree node and GridSubtree walker
struct GridSizingTreeNode {
  Member<GridItems> grid_items;
  GridLayoutData layout_data; // Holds GridSizingTrackCollection
  GridTrackSizingCollection column_track_collection;
  GridTrackSizingCollection row_track_collection;
  wtf_size_t subtree_size{1}; // Total nodes in this subtree (pre-order)
};

class GridSubtree {
  const GridSizingTree* tree_;
  wtf_size_t index_; // Current node index in pre-order traversal
public:
  GridSubtree FirstChild() const { return GridSubtree(tree_, index_ + 1); }
  GridSubtree NextSibling() const {
    return GridSubtree(tree_, index_ + tree_->SubtreeSize(index_));
  }
};
```
* **Invariant**: For any node at `index_`, its descendants occupy the contiguous slice `[index_ + 1, index_ + subtree_size - 1]`. Skipping an entire subgrid branch (e.g., when a subgrid has no subgridded axes) is an $O(1)$ index jump via `NextSibling()`.

### 1.2 `GridLineResolver`
Responsible for resolving raw CSS `grid-row-start`, `grid-column-end`, and `grid-template-areas` into 0-based explicit/implicit line numbers (`grid_line_resolver.h`).
* **Subgrid State**: Holds `std::optional<wtf_size_t> subgrid_span_size_`. When present, the axis is subgridded.
* **Resolution**:
  * Disables implicit track generation along the subgridded axis; out-of-bounds lines are strictly clamped to `[0, subgrid_span_size_]`.
  * Merges line names from three sources: (1) parent's inherited explicit/implicit line name sets sliced to the subgrid's span, (2) the subgrid’s own `grid-template-columns/rows: subgrid [line-name] ...` definitions, and (3) synthetic `[area-start]` / `[area-end]` names from inherited `grid-template-areas`.

### 1.3 `GridSpan` (SubgridLineRange)
In Blink (`grid_span.h`), line ranges are represented by `GridSpan`, which stores 0-based `start_line` and `end_line` (exclusive track index, inclusive end line index) in a translated coordinate system (where line `0` is the first implicit or explicit line).

```cpp
struct GridSpan {
  wtf_size_t start_line;
  wtf_size_t end_line;
  wtf_size_t IntegerSpan() const { return end_line - start_line; }
};
```
For a subgrid item $I$, its `GridSpan` is cached in `GridItemData` at every ancestor level it is subgridded into, translated into the respective ancestor’s coordinate space.

### 1.4 `ParentGridSizingContext` (`GridSizingTrackCollection` & `GridItemData`)
Rather than a standalone class named `ParentGridSizingContext`, Blink aggregates parent sizing context directly through `GridSizingTrackCollection` (`grid_track_collection.h`) and elevated `GridItemData` entries (`grid_item.h`).
* **Track Range Splitting**: Before track sizing begins, the root grid iterates through its entire `GridSizingTree`. Every subgrid item's translated `GridSpan` boundaries are registered into the ancestor's `GridRangeBuilder`. This splits the parent's `GridSizingTrackCollection` into atomic ranges (`GridRange`) so that a range boundary exists at every subgrid item start/end line.
* **Subgrid Properties in `GridItemData`**:
  * `bool is_subgrid_ : 1`
  * `bool has_subgridded_columns_ : 1`, `bool has_subgridded_rows_ : 1`
  * `NGBoxStrut subgrid_edge_margins_`: Accumulated margin/border/padding/gutter deltas from intermediate subgrids.

---

## 2. Inherited Track Slice Mapping

### 2.1 Coordinate System Definitions
* **W3C CSS Grid Spec**: Uses **1-based** line indices for explicit lines (with negative indices counting from the end, and $0$ invalid).
* **Blink Internal**: Uses **0-based** translated track/line indices. A grid with $N$ total tracks (implicit + explicit) has $N+1$ lines indexed $0, 1, \dots, N$. Track $t \in [0, N-1]$ is bounded by lines $t$ and $t+1$.

### 2.2 Line Index Translation Formula
Let a subgrid $S$ be placed on its parent grid $P$ spanning parent 0-based lines $[p_{\text{start}}, p_{\text{end}}]$ with span size $K = p_{\text{end}} - p_{\text{start}}$ ($K \ge 1$).

1. **W3C 1-based Local Line to Blink 0-based Local Line**:
   For a positive 1-based CSS line $L_{\text{css}} \in [1, K+1]$:
   $$l_{\text{local}} = \text{clamp}(L_{\text{css}} - 1, 0, K)$$
   For a negative 1-based CSS line $L_{\text{css}} \in [-(K+1), -1]$:
   $$l_{\text{local}} = \text{clamp}(K + 2 + L_{\text{css}} - 1, 0, K)$$

2. **Blink Local Line $[0, K]$ to Parent Line $[p_{\text{start}}, p_{\text{end}}]$**:
   $$T_{S \to P}(l_{\text{local}}) = p_{\text{start}} + l_{\text{local}}$$
   For a local item span $[l_{\text{start}}, l_{\text{end}}] \subseteq [0, K]$:
   $$[p'_{ \text{start}}, p'_{\text{end}}] = [p_{\text{start}} + l_{\text{start}}, \; p_{\text{start}} + l_{\text{end}}]$$

3. **Recursive Multi-Level Subgrid Composition**:
   Given a chain of nested subgrids $G_0 \supset G_1 \supset \dots \supset G_m$, where each $G_i$ ($i \ge 1$) is placed at parent $G_{i-1}$'s local span $[s_i, e_i]$, the absolute root grid ($G_0$) span for an item at $G_m$ with local span $[l_{\text{start}}, l_{\text{end}}]$ is:
   $$\text{RootSpan}([l_{\text{start}}, l_{\text{end}}]) = \left[ l_{\text{start}} + \sum_{i=1}^{m} s_i, \;\; l_{\text{end}} + \sum_{i=1}^{m} s_i \right]$$

### 2.3 `writing-mode` and `direction` Polarity Inversion
When the subgrid $S$'s block/inline flow direction opposes the parent $P$'s flow direction along the shared grid axis, a polarity inversion $\sigma(S, P) \in \{+1, -1\}$ occurs (`GridPositionsResolver` / `GridSizingTree::TranslateSubgridSpans`).
If $\sigma(S, P) = -1$ (reversed direction):
$$T^{\text{rev}}_{S \to P}(l_{\text{local}}) = p_{\text{end}} - l_{\text{local}}$$
And a local span $[l_{\text{start}}, l_{\text{end}}]$ maps to the parent span:
$$[p'_{\text{start}}, p'_{\text{end}}] = [p_{\text{end}} - l_{\text{end}}, \; p_{\text{end}} - l_{\text{start}}]$$

---

## 3. Track Sizing Contribution

In W3C Grid Level 2 §2.4 and Blink’s `GridLayoutAlgorithm::ResolveIntrinsicTrackSizes`, subgrids do not run an independent Track Sizing Algorithm for their subgridded axes. Instead, their items are lifted into the ancestor grid's `GridItems` collection during sizing.

```
Root GridSizingTrackCollection:  |--- Track 0 ---|--- Track 1 ---|--- Track 2 ---|--- Track 3 ---|
                                                 |================ Subgrid S (Span [1, 3]) ======|
                                                 |-- mbp_start --|               |--- mbp_end ---|
                                                 |---- Subgrid Item I (Local [0, 1] -> [1, 2]) --|
```

### 3.1 Lifting and Multi-Span Sorting
In Blink (`GridLayoutAlgorithm::BuildGridSizingSubtree`):
1. Any descendant item $I$ inside a subgrid $S$ whose axis is subgridded all the way to the current sizing grid $G$ is appended to $G$'s track sizing item list.
2. Each lifted item $I$ carries its translated `GridSpan` $[p'_{\text{start}}, p'_{\text{end}}]$ and references to the `GridSet`s in $G$'s `GridSizingTrackCollection`.
3. Items are bucketed into two groups per W3C Grid 1 §11.5:
   * **Group 1**: Items not spanning a flexible (`fr`) track, sorted in ascending order of span length $S(I) = p'_{\text{end}} - p'_{\text{start}}$ ($1, 2, \dots, N$).
   * **Group 2**: Items spanning at least one flexible (`fr`) track (processed together after all non-flex spans).
   Subgrid items and direct root grid items of the same span length $k$ are processed **simultaneously in a single batch** during Step 2 of `ResolveIntrinsicTrackSizes`.

### 3.2 Orthogonal / Independent Axis Dependency Cycle Resolution
When a subgrid is **single-axis** (e.g., `grid-template-columns: subgrid; grid-template-rows: auto;`), or when a subgrid has an orthogonal `writing-mode` relative to its parent, track sizing in one axis depends on layout results in the other:
1. **Pass 1 (Column Track Sizing)**: Root grid sizes columns. Single-axis column subgrids contribute their items' inline min/max-content sizes directly to root columns.
2. **Standalone Axis Sizing**: For a subgrid with standalone rows, when the root grid needs the subgrid container's block size (during root row sizing), Blink recursively invokes `ComputeMinMaxSizes` / `ResolveIntrinsicTrackSizes` on the subgrid's standalone row collection using the **already-resolved** inherited column track sizes from the parent.
3. **Pass 2 (Row Track Sizing)**: Root grid sizes rows.
4. **Re-resolution (if dependent)**: If root row sizes alter available inline percentages or orthogonal item constraints in column-subgrids, Blink detects the change via `needs_additional_pass` and re-runs column track sizing and dependent standalone subgrid axes (at most one extra cycle per Grid 1 §11.1).

---

## 4. Margin, Border, and Padding (MBP) & Gutter Handling at Subgrid Boundaries

Per W3C CSS Grid Layout Level 2 §2.3 & §2.5, a subgrid does not have its own implicit tracks, nor does it establish independent track sizes; however, its **margins, borders, scrollbar gutters, and padding (MBP)** at the edges of the subgrid, as well as the difference between the subgrid's `gap` and the parent's `gap`, must be accounted for in the first, last, and interior inherited tracks.

### 4.1 Extra Edge Margin Accumulation (`subgrid_edge_margins`)
Let a subgrid $S$ span parent tracks $[p_{\text{start}}, p_{\text{end}} - 1]$ (lines $[p_{\text{start}}, p_{\text{end}}]$).
Let $M_{\text{start}}(S), B_{\text{start}}(S), P_{\text{start}}(S)$ be the subgrid container's margin, border, and padding at the start edge of the axis, and similarly for the end edge:
$$\text{MBP}_{\text{start}}(S) = M_{\text{start}}(S) + B_{\text{start}}(S) + P_{\text{start}}(S)$$
$$\text{MBP}_{\text{end}}(S) = M_{\text{end}}(S) + B_{\text{end}}(S) + P_{\text{end}}(S)$$

### 4.2 Gutter (`gap`) Difference Adjustment
Let $g_P$ be the parent grid's gutter size (`column-gap` or `row-gap`) and $g_S$ be the subgrid $S$'s gutter size.
In CSS Grid Level 2 §2.4, the difference $\Delta g(S) = g_S - g_P$ acts as an imaginary margin applied symmetrically ($0.5 \cdot \Delta g(S)$) to each side of every interior line of the subgrid:
* For a subgrid local line $l \in [0, K]$:
  * Start side of local track $t \in [0, K-1]$ (at line $l = t$):
    $$\text{GutterDelta}_{\text{start}}(S, t) = \begin{cases} 0 & \text{if } t = 0 \\ \frac{1}{2}(g_S - g_P) & \text{if } t > 0 \end{cases}$$
  * End side of local track $t \in [0, K-1]$ (at line $l = t+1$):
    $$\text{GutterDelta}_{\text{end}}(S, t) = \begin{cases} 0 & \text{if } t = K - 1 \\ \frac{1}{2}(g_S - g_P) & \text{if } t < K - 1 \end{cases}$$

### 4.3 Combined Item Contribution Shim Formula
For an item $I$ inside subgrid $S$ occupying local span $[l_{\text{start}}, l_{\text{end}}] \subseteq [0, K]$ (so $l_{\text{start}}$ is the first track index and $l_{\text{end}} - 1$ is the last track index):
The extra start and end shim $\Delta_{\text{start}}(I, S)$ and $\Delta_{\text{end}}(I, S)$ added by subgrid $S$ to item $I$'s outer intrinsic size contribution is