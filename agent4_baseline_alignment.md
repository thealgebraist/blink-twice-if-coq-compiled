### 1. Core Data Structures in Chromium Blink

In Chromium's LayoutNG (`third_party/blink/renderer/core/layout/`), baseline alignment is orchestrated across inline, flex, grid, and table layout algorithms using a unified set of primitives and state machines.

#### `FontBaseline` (`core/layout/ng/inline/ng_baseline.h` / `platform/fonts/font_baseline.h`)
Defines the typographic reference metric used to compute the dominant baseline of a box:
```cpp
enum FontBaseline {
  kAlphabeticBaseline, // Default for horizontal typographic modes (latin, cyrillic, etc.)
  kIdeographicBaseline, // Used for vertical typographic modes (CJK) when text-orientation is mixed/upright
  kCentralBaseline     // Derived as (ascent - descent) / 2, used in specific SVG/vertical contexts
};
```

#### `ItemPosition` (`core/style/computed_style_constants.h`)
Represents the parsed CSS alignment values (`align-items`, `align-self`, `justify-items`, `justify-self`):
```cpp
enum class ItemPosition : uint8_t {
  // ...
  kBaseline,     // Maps to CSS `first baseline` (or `baseline`)
  kLastBaseline, // Maps to CSS `last baseline`
  // ...
};
```

#### `BaselineGroup` (e.g., `core/layout/grid/grid_baseline_accumulator.h`, `flex_line.h`)
A `BaselineGroup` aggregates items within a single alignment context that share both a *baseline-sharing preference* (first vs. last) and a *synthesized baseline orientation* (determined by the item's writing mode and direction relative to the container's alignment axis).

```cpp
class BaselineGroup {
  FontBaseline baseline_type_;
  LogicalBoxSides/*or WritingDirectionMode*/ group_orientation_;
  ItemPosition preference_; // kBaseline or kLastBaseline
  LayoutUnit max_ascent_ = LayoutUnit::Min();
  LayoutUnit max_descent_ = LayoutUnit::Min();
};
```

#### `PhysicalBoxFragment` / `NGBoxFragment` Baseline Interface
Layout passes export baseline offsets relative to the box's border-box block-start edge via `PhysicalBoxFragment`:
*   `FirstBaseline() -> std::optional<LayoutUnit>`
*   `LastBaseline() -> std::optional<LayoutUnit>`
*   `UseLastBaselineForInlineBaseline()`: Indicates whether an `inline-block` or `inline-table` uses its last baseline when participating in an outer inline formatting context.

---

### 2. First vs. Last Baseline Extraction Mechanics

Baseline extraction in Blink is resolved via `NGBoxFragment::BaselineMetrics` (and specialized algorithm methods like `FlexibleBoxAlgorithm::SynthesizeBaseline`), returning an offset from the box’s margin-box or border-box start edge. If a box has no natural baseline, one is *synthesized* from its border-box or margin-box edges.

| Box Type | First Baseline (`kBaseline`) | Last Baseline (`kLastBaseline`) | Fallback / Synthesis |
| :--- | :--- | :--- | :--- |
| **Line Boxes** | Extracted from the root inline box’s `FontMetrics` (`ascent`) and inline children's `max_ascent` during `NGInlineLayoutAlgorithm`. | Identical to First Baseline for a single line box. | N/A (Line boxes always possess font metrics from the strut). |
| **Block Containers (In-flow Lines)** | `FirstBaseline()` of the *first* formatted in-flow line box. | `LastBaseline()` of the *last* formatted in-flow line box. | If no line boxes exist (or if `overflow != visible` and `baseline-source` isn't explicit), synthesized from the block-end border edge (for inline-blocks) or margin edge. |
| **Inline-Block** | By default in CSS2.1 inline formatting contexts, an `inline-block` exports its *last* line box's baseline unless `baseline-source: first` is set. When participating in Flex/Grid `first baseline` alignment, Blink queries `FirstBaseline()`. | Exports the last in-flow line box's baseline. | If `overflow` is not `visible` (i.e., scroll container), the baseline is synthesized at the block-end margin edge (`margin_box_height`). |
| **Replaced Elements** (`<img>`, `<canvas>`, `<input>`) | Intrinsic baseline is `None` (except form controls with text, like `<input type="text">` or `<button>`). | Intrinsic baseline is `None` (unless text-bearing form control). | Synthesized at the block-end border edge (for inline layout) or block-end margin edge (in Flex/Grid layout contexts). |
| **Flex Items** (`NGFlexLayoutAlgorithm`) | 1. If the flex item has a definite exported `FirstBaseline()` from its inner layout, return `margin_start + FirstBaseline()`.<br>2. If inner layout is a flex container with row direction, use the first flex line's baseline. | 1. If the flex item has a definite exported `LastBaseline()`, return `margin_start + LastBaseline()`.<br>2. If inner layout is a flex container, use the last flex line's baseline. | If `FirstBaseline()` / `LastBaseline()` returns `nullopt`, synthesize using the item's block-end (or inline-end, depending on writing mode) border edge, plus the relevant start/end margins. |
| **Grid Items** (`NGGridLayoutAlgorithm`) | Queries `fragment.FirstBaseline()`. If the item is a nested grid, extracts the first baseline of the first row containing baseline-aligned items, or the first row with content. | Queries `fragment.LastBaseline()`. For nested grids, extracts from the last row. | Synthesized via `GridBaselineAccumulator`: falls back to the item's border-box block-end edge (for `kAlphabeticBaseline`) or center (for `kCentralBaseline`), offset by margins. |

---

### 3. Baseline Sharing Group Algorithm

When a layout container (Flex Line or Grid Track) processes items with `ItemPosition::kBaseline` or `ItemPosition::kLastBaseline`, it executes a three-phase algorithm:

#### Phase 1: Partitioning into Baseline-Sharing Groups
Items within the same alignment context (a single `FlexLine` or a single Grid Row/Column track) are partitioned into disjoint `BaselineGroup` instances based on a 3-tuple key:
$$\text{Key}_i = (\text{ AlignmentContext}_i, \text{ Preference}_i \in \{\text{First}, \text{Last}\}, \text{ CompatibilityOrientation}_i )$$

*   **Compatibility Orientation**: Determined by comparing the container's alignment axis with the item's `WritingDirectionMode`. Items with orthogonal flows that cannot share a baseline axis are excluded from baseline alignment and fall back to `start` / `flex-start` alignment. Items with opposing block-flow directions (e.g., `vertical-lr` vs `vertical-rl` in a horizontal-tb container) are placed in separate groups or have their ascent/descent inverted depending on the `FontBaseline` polarity.

#### Phase 2: Ascent and Descent Accumulation
For each item $i$ in a `BaselineGroup` $G$, let:
*   $H_i \ge 0$ be the item's outer (margin-box) size along the alignment axis:
    $$H_i = \text{margin}_{\text{start}, i} + \text{border\_box\_size}_i + \text{margin}_{\text{end}, i}$$
*   $B_{\text{raw}, i} \in [0, \text{border\_box\_size}_i]$ be the resolved (or synthesized) baseline offset from the item's border-box start edge.

The outer ascent $A_i$ and outer descent $D_i$ are computed as:

1.  **For First Baseline (`kBaseline`) with matching block flow:**
    $$A_i = \text{margin}_{\text{start}, i} + B_{\text{raw}, i}$$
    $$D_i = H_i - A_i = \text{border\_box\_size}_i - B_{\text{raw}, i} + \text{margin}_{\text{end}, i}$$

2.  **For Last Baseline (`kLastBaseline`) with matching block flow:**
    Blink measures `LastBaseline` either from the start edge or inverts the reference frame. In `GridBaselineAccumulator` and `FlexLine`, the effective ascent $A_i$ from the start edge is:
    $$A_i = \text{margin}_{\text{start}, i} + B_{\text{last\_raw}, i}$$
    $$D_i = H_i - A_i$$
    *(Note: When aligning to `last baseline` in a bottom-up alignment coordinate space, the roles of ascent and descent are symmetrically swapped relative to the end edge).*

The group accumulates the extrema over all member items $i \in G$:
$$A_G = \max_{i \in G} A_i$$
$$D_G = \max_{i \in G} D_i$$

The total spatial requirement (baseline shim bound) of the group $G$ is:
$$H_G = A_G + D_G$$

#### Phase 3: Box Shifting and Track/Line Sizing
1.  **Container Sizing Contribution**: The alignment context (Flex line cross-size or Grid intrinsic track size) expands to accommodate $H_G$:
    $$S_{\text{context}} = \max \left( H_G, \max_{j \notin G} H_j \right)$$
2.  **Item Positioning (Shifting)**:
    *   For a **First Baseline** group anchored to the context's start edge, the margin-box start offset $\Delta_i$ for item $i \in G$ is:
        $$\Delta_i = A_G - A_i$$
    *   For a **Last Baseline** group anchored to the context's end edge (of size $S_{\text{context}}$), the margin-box start offset $\Delta_i$ is:
        $$\Delta_i = S_{\text{context}} - (D_G + A_i) = (S_{\text{context}} - H_G) + (A_G - A_i)$$

---

### 4. Mathematical Invariants, Edge Cases, and W3C Divergences

#### Core Mathematical Invariants
1.  **Non-Negative Shift Offset ($\Delta_i \ge 0$)**:
    Since $A_G = \max_{j \in G} A_j$, it holds trivially for all $i \in G$ that $A_G \ge A_i \implies \Delta_i = A_G - A_i \ge 0$. No item is ever shifted outside the start boundary of its baseline group.
2.  **Item Size Conservation**:
    $\forall i \in G, \quad A_i + D_i = H_i$.
3.  **Group Bounds Conservation**:
    $$H_G = A_G + D_G = \max_{i \in G} A_i + \max_{j \in G} D_j \ge \max_{k \in G} (A_k + D_k) = \max_{k \in G} H_k$$
    The group height $H_G$ is always greater than or equal to the tallest individual item in the group, and bounded above by $\max_i H_i + \max_j H_j$.
4.  **Baseline Coincidence**:
    In container coordinates, the absolute baseline position of item $i$ is $\text{Pos}_{\text{baseline}}(i) = \Delta_i + A_i = (A_G - A_i) + A_i = A_G$, which is constant for all $i \in G$.

#### Edge Cases
*   **Negative Margins**: While $B_{\text{raw}, i} \ge 0$, negative $\text{margin}_{\text{start}, i}$ or $\text{margin}_{\text{end}, i}$ can cause $A_i < 0$ or $D_i < 0$, and $H_i < 0$. However, Invariants 1, 2, 3, and 4 remain strictly valid over $\mathbb{Z}$ (`LayoutUnit`), because $\max$ over signed integers preserves $A_G \ge A_i$ and $\max A_i + \max D_j \ge \max(A_k + D_k)$.
*   **Auto Margins in Flex/Grid**: Per CSS Box Alignment 3 § 8.3, if an item has `margin-top: auto` or `margin-bottom: auto` in the alignment axis, it *does not* participate in baseline alignment (auto margins absorb free space after sizing). Blink checks `HasAutoMarginsInCrossAxis()` and strips the item from the `BaselineGroup` before Phase 1.
*   **Subpixel / `LayoutUnit` Saturation**: Blink uses 26.6 fixed-point `LayoutUnit`. Extreme values near `LayoutUnit::Max()` can saturate during $A_G + D_G$, slightly violating strict linear equality in overflow regimes, though `Delta` remains non-negative due to clamping.

#### Divergences Between Chromium Blink and W3C CSS Box Alignment Level 3

| Feature / Area | W3C CSS Box Alignment Module Level 3 | Chromium Blink Implementation |
| :--- | :--- | :--- |
| **Fallback Alignment of `last baseline`** | Spec mandates that if `last baseline` cannot be satisfied (e.g., orthogonal flow with no baseline axis), its fallback alignment is `safe end` (or `flex-end`). | Blink historically falls back to `start` / `flex-start` in certain flexbox orthogonal writing-mode paths unless explicitly branched for `kLastBaseline`. |
| **Scroll Containers (`overflow != visible`)** | CSS Box Alignment 3 (and CSS Inline 3) states that for *inline-level* boxes, `overflow != visible` synthesizes the baseline at the margin-bottom edge, **but** for Flex and Grid items, the inner baseline of a scroll container *should* still be extracted from its in-flow content (at its initial scroll position). | Blink previously suppressed inner baselines for all `overflow != visible` boxes (inheriting the CSS2.1 `inline-block` rule). While updated in LayoutNG for Flex/Grid items via `ShouldUseContentBaseline()`, edge cases remain with nested scrollable `inline-block` descendants inside grid items. |
| **Intrinsic Sizing with Orthogonal Baseline Groups** | Spec defines complex cyclic dependency resolution when baseline alignment along a grid column axis depends on block layout of items whose inline size depends on the column track size. | Blink performs a two-pass heuristic in `NGGridLayoutAlgorithm`. It skips baseline contribution during the initial intrinsic inline-size pass if the item is orthogonal, occasionally under-sizing tracks compared to the theoretical fixed-point specified by W3C. |
| **Opposite Block-Flow Polarity Sharing** | Spec allows items with opposite block-flow directions (e.g., `vertical-lr` and `vertical-rl`) to share a single baseline group if their dominant baselines match, inverting ascent/descent relative to the line orientation. | In Grid (`GridBaselineAccumulator`), Blink separates items with inverted writing modes into distinct `BaselineGroup` buckets to avoid coordinate inversion complexities, preventing them from aligning baselines with each other. |

---

### 5. Formalization in Rocq / Coq (`BlinkBaselineAlignmentSemantics.v`)

The following self-contained Rocq (Coq) formalization models Blink's data structures, baseline extraction/synthesis, baseline-sharing group accumulation, shifting offsets, and proves all core mathematical invariants over arbitrary