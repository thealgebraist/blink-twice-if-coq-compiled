### 1. Core Data Structures in Blink Flex Wrapping

Blink’s LayoutNG Flexbox implementation (located in `third_party/blink/renderer/core/layout/flex/`) separates the algorithmic line-construction state from the physical layout state to support CSS Fragmentation (pagination/multi-column layout).

#### `FlexItem` & `FlexItemVectorView`
Before line breaking, Blink constructs a `HeapVector<NGFlexItem>` (or `FlexItem` in newer post-NG-prefix removal trees) representing the in-flow children ordered by the `order` property.
*   `flex_base_content_size`: $B_i$, the item's flex base size.
*   `hypothetical_main_content_size`: $H_i = \text{clamp}(B_i, \min_{\text{main}}, \max_{\text{main}})$.
*   `main_axis_border_padding`, `main_axis_margin`: $\text{BP}_i, M_i$.
*   `HypotheticalMainAxisMarginBoxSize()`: $H^{\text{outer}}_i = H_i + \text{BP}_i + M_i$.

#### `FlexLine` (Algorithmic vs. Physical)
Blink uses two distinct representations of a flex line during the lifecycle of `FlexLayoutAlgorithm::Layout()`:

1.  **Algorithmic State (`FlexLine` in `flexible_box_algorithm.h`)**:
    Constructed on-the-fly by `FlexLayoutAlgorithm::ComputeNextFlexLine()`.
    *   `line_items_`: A `FlexItemVectorView` (a span/slice `[start_index, end_index)` into the master `all_items_` vector).
    *   `sum_hypothetical_main_size_`: $\sum_{i \in \text{line}} H^{\text{outer}}_i + (|\text{line}| - 1) \cdot g_{\text{main}}$.
    *   ` sum_flex_base_size_`: $\sum_{i \in \text{line}} (B_i + \text{BP}_i + M_i) + (|\text{line}| - 1) \cdot g_{\text{main}}$.
    *   `cross_axis_size_`: $C_L$, the computed cross size of the line.
    *   `cross_axis_offset_`: $Y_L$, the offset of this line in the flex container's cross axis.
    *   `max_ major_ascent_`, `max_minor_ascent_`: Baseline alignment metrics.

2.  **Physical/Fragmentation State (`NGFlexLine` in `ng_flex_line.h`)**:
    Stored in `HeapVector<NGFlexLine> flex_lines` and persisted across fragmentation breaks inside `NGBreakToken` data (`NGFlexBreakTokenData`).
    *   `line_cross_size`: LayoutUnit.
    *   `cross_axis_offset`: LayoutUnit.
    *   `item_indices`: `Vector<wtf_size_t>` mapping back to children.
    *   `has_seen_all_children`: Boolean tracking if fragmentation interrupted the line.

#### `BreakTokens` in Multi-Line Flex (`NGFlexBreakTokenData`)
When a multi-line flex container is fragmented (e.g., inside a `multicol` container), Blink runs the entire W3C §9.3 and §9.4 algorithm *once* during the first fragment pass to compute the `HeapVector<NGFlexLine>` geometry, then caches this vector inside `NGFlexBreakTokenData`.
*   **Row-direction fragmentation**: Break tokens occur *between* `NGFlexLine`s or *inside* items of a `NGFlexLine`. `NGFlexBreakTokenData` stores `flex_lines` and `current_line_index`.
*   **Column-direction fragmentation**: Each column `FlexLine` runs parallel to the fragmentation progression axis. `BlockBreakToken`s are stored per-column-line so multiple flex lines can break simultaneously at the fragmentainer boundary.

---

### 2. Line Breaking Algorithm (W3C §9.3 vs. Blink)

#### Greedy Item Accumulation (`ComputeNextFlexLine`)
Let $W_{\text{avail}}$ be the `main_axis_inner_size_` of the flex container (which may be `LayoutUnit::Max()` if unconstrained/indefinite), and $g_m$ be `gap_between_items_`.

Blink iterates over `all_items_` starting from `next_item_index_`:

```cpp
// Conceptual distillation of FlexibleBoxAlgorithm::ComputeNextFlexLine
LayoutUnit sum_hypothetical_main_size;
wtf_size_t line_start_index = next_item_index_;

for (; next_item_index_ < all_items_.size(); ++next_item_index_) {
  const FlexItem& item = all_items_[next_item_index_];
  LayoutUnit item_outer_hypothetical = item.HypotheticalMainAxisMarginBoxSize();
  LayoutUnit gap = (next_item_index_ > line_start_index) ? gap_between_items_ : LayoutUnit();

  if (IsMultiline() && 
      next_item_index_ > line_start_index && // Never break before the first item on a line!
      sum_hypothetical_main_size + gap + item_outer_hypothetical > main_axis_inner_size_) {
    break;
  }
  sum_hypothetical_main_size += gap + item_outer_hypothetical;
  // Accumulate flex_base_size, factors, etc.
}
```

#### Wrap Mode Mechanics
1.  **`flex-wrap: nowrap`**:
    *   `IsMultiline()` returns `false`.
    *   The branch `if (IsMultiline() && ...)` is never taken.
    *   All items $[0, N)$ are placed into a single `FlexLine`. Even if $\sum H^{\text{outer}}_i > W_{\text{avail}}$, no line break occurs; the overflow is resolved in §9.7 via `flex-shrink` (or overflows the container if unshrinkable).
2.  **`flex-wrap: wrap`**:
    *   `IsMultiline()` returns `true`.
    *   Greedy accumulation partitions $[0, N)$ into contiguous non-empty slices $L_0, L_1, \dots, L_{k-1}$.
    *   Cross-axis progression matches the `writing-mode` block direction (for `flex-direction: row`) or inline direction (for `column`).
3.  **`flex-wrap: wrap-reverse`**:
    *   Item partitioning in `ComputeNextFlexLine()` is **identical** to `wrap`.
    *   Reversal occurs *after* §9.4 cross-size resolution in `FlipForWrapReverse()`:
        *   The cross-axis start edge and end edge are swapped.
        *   Line $L_0$ is placed at the cross-end edge (or after `align-content` offset inversion), and subsequent lines stack toward cross-start.
        *   In Blink, `cross_axis_offset` of each line is transformed via:
            $$Y'_L = C_{\text{container}} - Y_L - C_L$$
            and `align-content: flex-start` maps to physical cross-end, while `flex-end` maps to physical cross-start.

---

### 3. Cross-Size Determination & `align-content` (W3C §9.4)

Once lines are partitioned and §9.7 (`ResolveFlexibleLengths`) has fixed the main size of every item on every line, Blink lays out the items to find their hypothetical cross sizes $C^{\text{hyp}}_i$.

#### Step 1: Per-Line Cross Size ($C^{\text{init}}_L$) — §9.4.8
For a single-line container (`!IsMultiline()`) with a **definite** container cross size $C_{\text{def}}$:
$$C_0 = C_{\text{def}}$$

Otherwise (multi-line OR indefinite single-line), for each line $L$:
1.  Partition items $i \in L$ into two sets:
    *   $B_L$: Items with `align-self: baseline` (or `last baseline`), main-axis parallel to inline-axis, and no cross-axis `auto` margins.
    *   $O_L = L \setminus B_L$: All other items.
2.  For $i \in B_L$, compute the baseline ascent $a_i$ (distance from cross-start margin edge to baseline) and descent $d_i = C^{\text{outer}}_i - a_i$.
    $$A_L = \max_{i \in B_L} a_i, \quad D_L = \max_{i \in B_L} d_i$$
3.  For $i \in O_L$, record the outer hypothetical cross size $C^{\text{outer}}_i$.
4.  The initial line cross size is:
    $$C^{\text{init}}_L = \max\left( A_L + D_L, \max_{i \in O_L} C^{\text{outer}}_i \right)$$
5.  If the container is single-line (`nowrap`) and has `min-cross-size` / `max-cross-size`, clamp $C^{\text{init}}_0$ to $[\min_{\text{cross}}, \max_{\text{cross}}]$.

#### Step 2: `align-content` Distribution — §9.4.9 & §9.4.16
Let $K = |\text{lines}|$, $g_c$ be `gap_between_lines_` (`row-gap` or `column-gap`), and $C_{\text{avail}}$ be the container’s definite inner cross size (or $\sum_{L=0}^{K-1} C^{\text{init}}_L + (K-1)g_c$ clamped to min/max constraints if indefinite).

Define the **Free Cross Space** ($F_c$):
$$F_c = C_{\text{avail}} - \left( \sum_{L=0}^{K-1} C^{\text{init}}_L + (K - 1) \cdot g_c \right)$$

Blink computes the final line cross sizes $C_L$, initial cross offset $Y_0$, and inter-line spacing $\Delta Y$ in `FlexLayoutAlgorithm::GiveLinesAndItemsFinalPositionAndSize()`:

| `align-content` | Condition | Line Size $C_L$ | Initial Offset $Y_0$ | Inter-Line Step ($Y_{L} - (Y_{L-1} + C_{L-1})$) |
| :--- | :--- | :--- | :--- | :--- |
| **`stretch`** (default) | $F_c > 0$ | $C^{\text{init}}_L + \frac{F_c}{K}$ | $0$ | $g_c$ |
| **`stretch`** | $F_c \le 0$ | $C^{\text{init}}_L$ | $0$ | $g_c$ |
| **`flex-start`** | All $F_c$ | $C^{\text{init}}_L$ | $0$ | $g_c$ |
| **`flex-end`** | All $F_c$ | $C^{\text{init}}_L$ | $F_c$ | $g_c$ |
| **`center`** | All $F_c$ | $C^{\text{init}}_L$ | $\frac{F_c}{2}$ | $g_c$ |
| **`space-between`**| $F_c \ge 0 \land K > 1$ | $C^{\text{init}}_L$ | $0$ | $g_c + \frac{F_c}{K - 1}$ |
| **`space-between`**| $F_c < 0 \lor K = 1$ | $C^{\text{init}}_L$ | $0$ (fallback: `flex-start`) | $g_c$ |
| **`space-around`** | $F_c \ge 0 \land K \ge 1$ | $C^{\text{init}}_L$ | $\frac{F_c}{2K}$ | $g_c + \frac{F_c}{K}$ |
| **`space-around`** | $F_c < 0$ | $C^{\text{init}}_L$ | $\frac{F_c}{2}$ (fallback: `safe`/`center`) | $g_c$ |
| **`space-evenly`** *(CSS Box Align 3)* | $F_c \ge 0 \land K \ge 1$ | $C^{\text{init}}_L$ | $\frac{F_c}{K + 1}$ | $g_c + \frac{F_c}{K + 1}$ |

*(Note: For `wrap-reverse`, `flex-start` and `flex-end` swap their fallback and initial offset rules before or during coordinate inversion).*

---

### 4. Mathematical Invariants, Edge Cases, and W3C vs. Blink Gaps

#### Core Mathematical Invariants
1.  **Strict Monotonic Contiguous Partitioning**:
    Given items $I = [0, 1, \dots, N-1]$ with $N > 0$, line breaking produces lines $L_0, \dots, L_{K-1}$ where each $L_j = [s_j, e_j)$ such that:
    *   $s_0 = 0 \land e_{K-1} = N$
    *   $\forall j \in [0, K-1),\ s_j < e_j$ *(Non-emptiness / Termination progress)*
    *   $\forall j \in [0, K-2],\ e_j = s_{j+1}$ *(Contiguity)*
2.  **Greedy Optimality (Maximal Packing)**:
    For every line $L_j = [s_j, e_j)$ with $j < K-1$ (when `IsMultiline()` is true):
    $$\left( \sum_{i=s_j}^{e_j - 1} H^{\text{outer}}_i + (e_j - 1 - s_j) g_m \right) + g_m + H^{\text{outer}}_{e_j} > W_{\text{avail}}$$
    And if $e_j - s_j > 1$:
    $$\sum_{i=s_j}^{e_j - 1} H^{\text{outer}}_i + (e_j - 1 - s_j) g_m \le W_{\text{avail}}$$
3.  **Cross-Size Conservation under `stretch` ($F_c \ge 0$)**:
    $$\sum_{L=0}^{K-1} C_L + (K - 1) g_c = C_{\text{avail}}$$
    *(Subject to fixed-point rounding quantization in Blink; see Gaps below).*

#### Edge Cases
1.  **Oversized Single Item ($H^{\text{outer}}_i > W_{\text{avail}}$)**:
    If $i = s_j$, the loop guard `next_item_index_ > line_start_index` is `false`. The item is forced onto $L_j$, and the subsequent item $i+1$ immediately triggers the break condition, leaving $L_j = [i, i+1)$ as a singleton line with `sum_hyp