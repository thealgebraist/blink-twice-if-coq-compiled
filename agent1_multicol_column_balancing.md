## 1. Core Data Structures in Blink Column Balancing

In Chromium’s Blink rendering engine (specifically within the LayoutNG/BlinkNG architecture under `third_party/blink/renderer/core/layout/`), multi-column layout is orchestrated by `ColumnLayoutAlgorithm`. Below is the architectural mapping of the core data structures and primitives used during multi-column sizing and balancing.

### `ColumnLayoutAlgorithm`
Inherits from `LayoutAlgorithm<BlockNode, BoxFragmentBuilder, BlockBreakToken>`. It is responsible for breaking block-level flow content into column fragments and handling column spanners (`column-span: all`).
*   **Inputs:** `LayoutAlgorithmParams` containing `BlockNode` (the multicol container), `ConstraintSpace` (available inline/block sizes, fragmentation directives), and an incoming `BlockBreakToken` (if the multicol container itself is nested inside an outer fragmentation context, like pagination or another multicol).
*   **Internal State:**
    *   `int used_column_count_`: Resolved number of columns ($N$).
    *   `LayoutUnit column_inline_size_`: Resolved inline size of an individual column ($W_{used}$).
    *   `LayoutUnit column_Inline_progression_`: Stride between adjacent columns ($W_{used} + G$).
    *   `LayoutUnit intrinsic_block_size_`: Accumulated block size of column rows and spanners.
    *   `bool is_constrained_by_outer_fragmentation_context_`: Tracks whether outer fragmentation limits maximum column height.

### `ColumnBalancingInfo` (and Space Shortage Mechanics)
While legacy Blink used an explicit struct, LayoutNG/BlinkNG distributes column balancing state across an internal evaluation pass and the `BoxFragmentBuilder` / `LayoutResult` return path:
*   `minimal_space_shortage_` (`std::optional<LayoutUnit>`): Propagated upward via `LayoutResult::MinimalSpaceShortage()`. It records the smallest amount of extra block size needed by any fragmented child to pull at least one unbreakable unit (e.g., a line box or atomic inline) from column $i+1$ back into column $i$.
*   `tallest_unbreakable_block_size_` (`LayoutUnit`): Propagated via `BoxFragmentBuilder` during an initial unconstrained or zero-height layout pass when `IsInitialColumnBalancingPass()` is active in `ConstraintSpace`. It tracks the maximum block size of any monolithic (unbreakable) child element (e.g., an image, a line box, or a `break-inside: avoid` block).
*   `num_content_breaks_` (`int`): Count of explicit (forced) breaks (`break-before: column`, `break-after: column`) encountered during the column row pass.
*   `total_content_block_size_` (`LayoutUnit`): Total accumulated block height across all generated columns during a test pass.

### Primitive Representations: `ColumnWidth`, `ColumnCount`, `ColumnGap`
Blink represents all layout lengths using fixed-point arithmetic (`LayoutUnit`, which uses 6 fractional bits, i.e., $1/64\text{th}$ of a CSS pixel, stored in an underlying `int32_t`).

*   **`ColumnWidth`**: Stored on `ComputedStyle` as a `float` alongside a boolean flag `HasAutoColumnWidth()`. During layout, if non-auto, it is clamped and converted to `LayoutUnit`:
    $$\text{ColumnWidth} \in \{\text{Auto}\} \cup \{w \in \text{LayoutUnit} \mid w \ge 0\}$$
*   **`ColumnCount`**: Stored on `ComputedStyle` as an `uint16_t` alongside `HasAutoColumnCount()`:
    $$\text{ColumnCount} \in \{\text{Auto}\} \cup \{c \in \mathbb{Z}^+ \mid 1 \le c \le \text{kMaxColumnCount}\}$$
*   **`ColumnGap`**: Retrieved via `ResolveColumnGapLength()`. In CSS Sizing/Align, `normal` resolves to `1em` in standard multicol contexts, or a `Length` (fixed or percentage of `available_inline_size`), clamped to $\ge 0$:
    $$\text{ColumnGap} \in \{g \in \text{LayoutUnit} \mid g \ge 0\}$$

---

## 2. Sizing Calculation: Inline Size Resolution

The pseudo-algorithm in **W3C CSS Multi-column Layout Module Level 1 (Section 3.4)** resolves `column-width` ($W_{spec}$) and `column-count` ($N_{spec}$) into used values $W_{used}$ and $N_{used}$. In Blink, this is implemented in `ResolveUsedColumnInlineSize` and `ResolveUsedColumnCount` inside `length_utils.cc`.

Let:
*   $U \in \text{LayoutUnit}$ be the `available_inline_size` (content-box inline size of the multicol container).
*   $G \in \text{LayoutUnit}$ be the resolved `column-gap` ($G \ge 0$).
*   $W_{spec} \in \{\text{Auto}\} \cup \text{LayoutUnit}$ be the computed `column-width`.
*   $N_{spec} \in \{\text{Auto}\} \cup \mathbb{Z}^+$ be the computed `column-count`.

### Step 1: Base Column Count ($N$) Resolution
1.  **Case A: $W_{spec} = \text{Auto}$ and $N_{spec} \neq \text{Auto}$**
    $$N = N_{spec}$$
2.  **Case B: $W_{spec} \neq \text{Auto}$ and $N_{spec} = \text{Auto}$**
    First, Blink clamps the specified column width to a non-negative base width bounded by available space (or at least $1\text{px}$ / `LayoutUnit::FromFloatCeil` in zero-prevention paths, though your target specification clamps to `available_inline`):
    $$W_{base} = \max(0, \min(U, W_{spec}))$$
    *(Note: To prevent division by zero when $W_{base} + G = 0$, Blink enforces a minimum divisor or checks $W_{spec} > 0$, as CSS grammar dictates `<length [0,∞]>` where $0\text{px}$ is clamped to a minimum positive `LayoutUnit::Epsilon()` or $1\text{px}$).*
    Then, the number of columns that can fit is:
    $$N = \max\left(1, \left\lfloor \frac{U + G}{W_{base} + G} \right\rfloor\right)$$
3.  **Case C: $W_{spec} \neq \text{Auto}$ and $N_{spec} \neq \text{Auto}$**
    $$N = \max\left(1, \min\left(N_{spec}, \left\lfloor \frac{U + G}{W_{base} + G} \right\rfloor\right)\right)$$

### Step 2: Extra Inline Space Distribution ($W_{used}$)
Once $N$ is determined, the total inline space consumed by the $N - 1$ inter-column gaps is $(N - 1) \cdot G$. The remaining inline space is distributed equally among the $N$ columns:
$$W_{raw} = \frac{U - (N - 1) \cdot G}{N}$$

To ensure non-negativity when total gaps exceed $U$ (i.e., $(N - 1) \cdot G > U$), Blink clamps the result:
$$W_{used} = \max\left(0, \left\lfloor \frac{U - (N - 1) \cdot G}{N} \right\rfloor_{\text{LayoutUnit}}\right)$$

In integer / fixed-point `LayoutUnit` arithmetic, integer division truncates fractional fixed-point units:
$$U = N \cdot W_{used} + (N - 1) \cdot G + R, \quad \text{where } 0 \le R < N \cdot \epsilon \text{ (when } U \ge (N-1)G\text{)}$$
The remainder $R$ is absorbed at the trailing inline edge of the multicol container (not distributed column-by-column).

---

## 3. Multi-Pass Column Balancing Loop

When `column-fill: balance` is active (the default for unconstrained block sizes, or constrained block sizes when `column-fill: balance-all` / unconstrained row precedes a spanner), Blink must find the **minimal column block size** $H$ such that all content fits within at most $N$ columns (excluding forced breaks).

### Step 1: Initial Bounding Pass (`CalculateBalancedColumnBlockSize`)
Blink runs an initial layout pass over the current column row with an unconstrained block size (or the container's max-height constraint) and `IsInitialColumnBalancingPass() = true`.
During this pass:
1.  Content is laid out into one (or more, if forced breaks exist) tall column fragments.
2.  Each fragment and child records its contribution to total block size and tracks `TallestUnbreakableBlockSize` ($M$).
3.  Forced breaks (`break-before: column`, `break-after: column`) split the content into $K + 1$ explicit segments (where $K$ is the number of forced breaks).

Let $T$ be the `total_block_size` accumulated across all fragments in the row, and $M$ be the `tallest_unbreakable_block_size` (equivalent to `max_child_block_size` for monolithic atomic children).

The initial lower bound $H_0$ for the column height is established as:
$$H_0 = \max\left(\left\lceil \frac{T}{N} \right\rceil, M\right)$$

*(Note: In Blink's `ColumnLayoutAlgorithm`, if there are forced breaks, Blink maintains a list of `ContentRuns`. Each run has a block size $T_i$, and runs are greedily subdivided across the remaining available columns $N - K$ by always splitting the tallest run until $N$ runs exist, taking $H_0 = \max(\max_i \lceil T_i / k_i \rceil, M)$).*

### Step 2: Iterative Relaxation via `minimal_space_shortage`
Why isn't $H_0$ immediately the final height? Because block fragmentation is discrete (quantized by line heights, margins, widows/orphans, and atomic blocks). At height $H_0$, content that summed to $T$ might break earlier in columns $1 \dots N$, causing spillover into an $(N+1)$-th "overflow" column.

Instead of a blind binary search over $[H_0, T]$ (which could take $\log_2(T/\epsilon)$ layout passes), Blink uses **Iterative Space-Shortage Relaxation**:

```
H = max(ceil(T / N), M)
loop:
    Run layout pass with column block-size constraint = H
    Let C = actual number of columns generated (excluding forced-break overflow)
    Let S = minimal_space_shortage recorded across all column breaks in this pass
    
    if C <= N:
        break // Converged! All content fits within N columns.
    
    if S is undefined or S <= 0:
        // Fallback safety invariant: prevent infinite loops
        break
        
    H = H + S
```

### How `minimal_space_shortage` ($S$) is Computed
When laying out column $i$ with target height $H$:
*   Suppose a child block or line box of height $h_{child}$ is encountered at offset $y < H$, such that $y + h_{child} > H$.
*   Because the child cannot fit in column $i$, it breaks (or is pushed whole) to column $i+1$.
*   The **space shortage** at this break point is:
    $$s_i = (y + h_{child}) - H > 0$$
*   If the column height were increased by $s_i$, this specific unit of content would fit into column $i$.
*   Across all columns $1 \dots C$ in a single pass, Blink tracks the minimum positive shortage:
    $$S = \min_{i \,:\, s_i > 0} s_i$$

By incrementing $H_{k+1} = H_k + S$, Blink jumps to the **exact next discrete threshold** where at least one column break changes position, guaranteeing optimal minimal height without wasted binary-search probing in dead zones where layout does not change.

---

## 4. Mathematical Formulas and Invariants

### Invariant 1: Non-Negative Column Dimensions
For all valid inputs $U \ge 0, G \ge 0, W_{spec} > 0, N_{spec} \ge 1$:
$$N \ge 1 \quad \land \quad W_{used} \ge 0 \quad \land \quad H \ge 0$$

### Invariant 2: Inline Space Conservation
When $U \ge (N - 1) \cdot G$, the total inline footprint of columns and gaps never exceeds the available inline size $U$, and the unallocated remainder $R$ is strictly bounded by the column count $N$:
$$0 \le U - \Big(N \cdot W_{used} + (N - 1) \cdot G\Big) < N \cdot \epsilon$$
In exact real arithmetic ($\mathbb{R}$), $N \cdot W_{used} + (N - 1) \cdot G = U$.
When $U < (N - 1) \cdot G$ (gap overflow), $W_{used} = 0$, and the gaps overflow the container inline box by $(N - 1) \cdot G - U$.

### Invariant 3: Monotonic Column Balancing Convergence
Let $H_k$ be the candidate column height at iteration $k$, with $H_0 = \max(\lceil T / N \rceil, M)$.
1.  **Strict Monotonicity of Height:** At every non-terminal step $k$, since $S_k \ge \epsilon > 0$ (where $\epsilon = 1\text{ LayoutUnit}$):
    $$H_{k+1} = H_k + S_k > H_k$$
2.  **Upper Bound:** At $H = T$, all content fits into $1 \le N$ column (assuming no forced breaks exceed $N$). Therefore, for any monotonic fragmentation function $\text{Cols}(H)$ where $H_1 \le H_2 \implies \text{Cols}(H_1) \ge \text{Cols}(H_2)$, the iteration is bounded above by $T$:
    $$H_0 \le H_k \le T$$
3.  **Finite Termination:** Since $H_k$ increases by at least $1$ discrete unit ($\epsilon$) per step and is bounded above by $T$, the loop terminates in at most $T - H_0$ steps (and in practice, bounded by the number of breakable atomic items, typically $1$ to $3$ passes).

---

## 5. Edge Cases & Divergences: Blink vs. W3C CSS Multicol Level 1

| Area | W3C CSS Multicol Level 1 Specification | Chromium Blink (`ColumnLayoutAlgorithm`) |
| :--- | :--- | :--- |
| **`column-width: 0px`** | Spec states `<length [0,∞]>`, and Section 3.4 notes that used `column-width` must be $>0$, clamping $0$ to a minimal value or treating it as invalid during $N$ calculation. | Blink clamps specified `column-width` during `ResolveUsedColumnCount` to at least `LayoutUnit(1)` (