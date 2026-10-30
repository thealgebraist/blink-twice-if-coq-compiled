**AUDIT REPORT: Blink Masonry Layout Engine**
**Agent ID:** 392
**Subject:** Shortest Column Placement & Minimal Column Index Selection (`grid-auto-flow: masonry` / `masonry-auto-flow`)

---

### 1. Executive Summary
This audit details the heuristic used by the Blink rendering engine (`LayoutMasonry` / `MasonryLayoutAlgorithm` within LayoutNG) to determine track placement when placing items into the shortest available column (or row, depending on the grid axis). Specifically, this covers the **Minimal Column Index Selection** algorithm, including tie-breaking rules, spanning item resolution, and layout tolerance thresholds.

---

### 2. Core Data Structures
During the masonry layout pass, Blink maintains an array of running positions representing the current "bottom" (block-end) of each grid track in the masonry axis:

*   `Vector<LayoutUnit> running_positions`: Stores the accumulated block-size of items placed in each track, indexed from `0` to `N-1` (where `N` is the number of tracks in the grid axis).
*   `LayoutUnit`: Blink’s subpixel-precision unit (typically $1/64\text{th}$ of a CSS pixel).

---

### 3. Minimal Column Index Selection Algorithm

When an item with an auto-placement cursor is evaluated (and `masonry-auto-flow: next` is **not** forced), Blink executes the following selection logic to find the optimal track index $i_{min}$.

#### A. Single-Track Items (Span = 1)
For an item spanning a single track, the engine scans the `running_positions` vector to find the absolute minimum value:

$$i_{min} = \arg\min_{i \in [0, N-1]} (\text{running\_positions}[i])$$

**Tie-Breaking Rule (First-Fit):**
The iteration proceeds strictly in grid-order (index `0` to `N-1`). The comparison uses a strict less-than operator (`<`) rather than less-than-or-equal-to (`<=`):

```cpp
LayoutUnit min_position = LayoutUnit::Max();
wtf_size_t min_index = 0;

for (wtf_size_t i = 0; i < num_tracks; ++i) {
  // Strict inequality ensures the lowest index wins ties.
  if (running_positions[i] < min_position) {
    min_position = running_positions[i];
    min_index = i;
  }
}
```
*   **Note on RTL / Directionality:** "Index `0`" represents the logical `inline-start` track. In `dir="rtl"`, index `0` is the rightmost visual column.

#### B. Multi-Track Items (Span $S > 1$)
When an item spans $S$ tracks, it cannot be placed in a single column; it bridges a contiguous range of columns $[i, i + S - 1]$. 

1.  **Effective Starting Position Calculation:** For every valid starting index $i \in [0, N - S]$, Blink calculates the *maximum* running position within that span window (as the item must sit flat across the tallest column in that group):
    $$H_{span}(i) = \max_{k \in [i, i + S - 1]} (\text{running\_positions}[k])$$
2.  **Minimum Window Selection:** Blink then selects the starting index $i_{min}$ that yields the lowest $H_{span}(i)$:
    $$i_{min} = \arg\min_{i \in [0, N - S]} H_{span}(i)$$
3.  **Update Phase:** Once placed, **all** tracks in the range $[i_{min}, i_{min} + S - 1]$ have their `running_positions` updated to $H_{span}(i_{min}) + \text{item\_block\_size} + \text{gap}$. (This creates the potential for layout "holes" unless back-filling/dense packing is triggered).

---

### 4. Subpixel Tolerance & "Slack" Factor (`item-tolerance` / `masonry-slack`)
A critical edge case in Blink's minimal index selection is **subpixel quantization**. 

If Column 0 has a running position of `100.015px` (6401 subpixels) and Column 3 has a running position of `100.000px` (6400 subpixels) due to fractional percentage widths or aspect-ratio calculations, a strict `<` check would place the next item in Column 3, violating the user's visual expectation of a left-to-right flow across seemingly equal columns.

To mitigate this, Blink implements the CSS Grid/Masonry tolerance specification (`item-tolerance`, formerly `masonry-slack`):
*   **Default Tolerance ($\epsilon$):** `1em` (resolved to `LayoutUnit` at layout time).
*   **Modified Selection Logic:**
    1. Blink first finds the true absolute minimum position: $P_{min} = \min(\text{running\_positions})$.
    2. It then re-scans from index `0` to $N-1$ and selects the **first** column $i$ that satisfies:
       $$\text{running\_positions}[i] \le P_{min} + \epsilon$$

```cpp
// Pass 1: Find absolute minimum
LayoutUnit min_pos = FindAbsoluteMinimum(running_positions);
LayoutUnit threshold = min_pos + item_tolerance;

// Pass 2: Select lowest index within tolerance
for (wtf_size_t i = 0; i < num_tracks; ++i) {
  if (running_positions[i] <= threshold) {
    return i; // Minimal valid index selected
  }
}
```

---

### 5. Audit Findings & Edge Cases

1.  **Explicit Grid-Axis Placement Override:** If an item has an explicit `grid-column-start: K`, the minimal index selection algorithm is bypassed entirely. The item is forced into track $K$, and `running_positions[K]` is incremented regardless of its height relative to other columns.
2.  **Negative Margins:** Items with negative block margins can cause `running_positions[i]` to *decrease* after placement. The selection algorithm handles this natively via signed `LayoutUnit` arithmetic, potentially causing subsequent items to cluster in that column until it catches up.
3.  **Performance Complexity:** Current implementation is $O(N)$ per item (where $N$ is track count), resulting in $O(M \times N)$ for $M$ items. For extreme track counts ($N > 1000$), a Min-Heap / Priority Queue or Segment Tree (for spanning items) is recommended to reduce lookup to $O(\log N)$.

**Status:** Algorithm verified against Blink LayoutNG specification. **Audit Complete.**