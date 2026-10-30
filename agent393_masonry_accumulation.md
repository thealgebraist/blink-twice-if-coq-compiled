**AUDIT REPORT: Blink LayoutNG Masonry**
**Agent ID:** 393
**Subject:** Monotonic Accumulation Property in Masonry Track Sizing (`LayoutUnit` Clamping & Precision)

---

### 1. Executive Summary
In Blink’s LayoutNG implementation of CSS Masonry, the **Monotonic Accumulation Property** dictates that the running block-size (height, in horizontal writing modes) of any given masonry grid track must be non-decreasing ($H_{i} \ge H_{i-1}$) as standard-flow items are placed into it. 

While mathematically trivial in infinite-precision arithmetic, enforcing this property within Blink’s fixed-point `LayoutUnit` system requires strict adherence to saturation arithmetic, margin-strut resolution, and negative-size clamping. Failure to maintain monotonicity results in **Track Selection Inversion**, **Infinite Layout Loops**, and **Subpixel Oscillation**.

---

### 2. Mathematical Definition in LayoutNG
Let $T_k$ be a masonry track at index $k$. Let $H_k(n)$ be the accumulated block-size of track $T_k$ after placing $n$ items. 

When placing the $(n+1)$-th item into $T_k$, the new height is calculated as:

$$H_k(n+1) = H_k(n) + \Delta_B$$

Where the block-axis delta $\Delta_B$ is:

$$\Delta_B = \text{Margin}_{\text{start}} + \text{BlockSize}_{\text{border-box}} + \text{Margin}_{\text{end}} + \text{RowGap}$$

For the **Monotonic Accumulation Property** to hold strictly:
$$\forall n \ge 0, \quad H_k(n+1) \ge H_k(n) \implies \Delta_B \ge 0$$

*Note: In CSS Grid/Masonry, margins do not collapse between items in the masonry axis, simplifying $\Delta_B$ to a purely additive operation, though negative margins remain a threat vector.*

---

### 3. The "Shortest-Track" Heuristic Dependency
The core Masonry placement algorithm relies on a greedy heuristic: **place the next item into the track with the minimum accumulated running position.**

$$T_{\text{target}} = \arg\min_{k} \left( H_k(n) \right)$$

Monotonicity is the foundational invariant that guarantees forward progress in the block axis. If $\Delta_B < 0$ is permitted (violating monotonicity), $H_k(n+1) < H_k(n)$. This causes the track’s running position to regress upwards, leading to:
1. **Z-Order/DOM-Order Visual Thrashing:** Subsequent items are placed *above* previously placed items in the same track.
2. **Track Starvation:** A track with a heavily negative $\Delta_B$ becomes a "gravity well," repeatedly winning the $\arg\min$ check and absorbing all subsequent grid items until its height catches up to the rest of the grid.

---

### 4. Blink Implementation Audit Vectors

As Agent 393, my audit of the Blink codebase (`third_party/blink/renderer/core/layout/masonry/` and `grid/`) focuses on three specific failure modes where monotonic accumulation can be violated or corrupted.

#### Vector A: Negative Outer Sizes ($\Delta_B < 0$)
While `BlockSize` (border-box) is clamped at `LayoutUnit(0)` by the fragment builder, CSS allows negative margins. If an item has `height: 10px; margin-bottom: -20px;`, its outer block size is `-10px`.
* **Audit Requirement:** Verify whether the CSS WG specification for Masonry dictates clamping the *outer* size of the item at zero before accumulation, or if true monotonic accumulation is relaxed in the presence of negative margins.
* **Blink Invariant:** Even if negative margins allow local regression of the running position, the *intrinsic block size* contribution of the track to the Masonry container must remain monotonic via `std::max(max_track_height, current_running_pos)`.

#### Vector B: `LayoutUnit` Saturation Arithmetic (The `kMax` Plateau)
Blink uses `LayoutUnit` (a 32-bit signed fixed-point value with 6 fractional bits, max value $\approx 33.55\text{ million pixels}$).
* **The Flaw:** Standard integer addition overflows into negative territory ($H_k(n) + \Delta_B < 0$), catastrophic for monotonicity.
* **The Mitigation:** Blink’s `LayoutUnit` overloads `operator+` to use **saturated addition** (`ClampAdd`).
* **The Audit Edge Case:** Once a track hits `LayoutUnit::Max()`, $H_k(n+1) = H_k(n)$ becomes strictly equal (a monotonic plateau). If *all* tracks saturate during a fuzzer test (e.g., `height: 99999999px`), the $\arg\min$ function must deterministically pick the first track (index $0$) rather than failing or oscillating due to floating-point-to-LayoutUnit conversion discrepancies.

#### Vector C: Subpixel Accumulation & Spanning Items
When an item spans multiple masonry tracks (e.g., `grid-column: span 2`), its placement height is determined by the *maximum* height of the spanned tracks:

$$H_{\text{base}} = \max_{j \in \text{span}} H_j(n)$$

After placing the spanning item, *all* tracks in the span are updated to:

$$H_j(n+1) = H_{\text{base}} + \Delta_B$$

* **Monotonicity Verification:** Because $H_{\text{base}} \ge H_j(n)$ for all $j$ in the span, and assuming $\Delta_B \ge 0$, it is guaranteed that $H_j(n+1) \ge H_j(n)$. In in-between tracks, the height leaps forward (a discontinuous monotonic step).
* **Subpixel Audit:** Ensure that when `row-gap` or percentage margins resolve to fractional `LayoutUnit` values (multiples of $\frac{1}{64}\text{px}$), they are truncated/rounded *prior* to accumulation. Accumulating raw `float` values and converting to `LayoutUnit` only at the end of layout will cause non-monotonic rounding jitter between layout passes.

---

### 5. Recommended C++ Assertions for Blink (`masonry_layout_algorithm.cc`)

To enforce this property during layout passes, the following `DCHECK` invariants should be maintained in the track collection tracker:

```cpp
void MasonryRunningPositions::AccumulateTrackHeight(
    wtf_size_t track_index,
    LayoutUnit item_margin_box_block_size,
    LayoutUnit block_gap) {
  
  LayoutUnit previous_height = running_positions_[track_index];
  
  // Ensure we do not regress if strict monotonicity is enforced on outer sizes.
  // Note: Remove std::max if CSSWG permits negative margin regression in Masonry.
  LayoutUnit delta = std::max(LayoutUnit(), item_margin_box_block_size) + block_gap;
  
  // LayoutUnit::operator+= performs saturated addition automatically.
  running_positions_[track_index] += delta;

  // AUDIT INVARIANT 393-A: Monotonic Accumulation Check
  DCHECK_GE(running_positions_[track_index], previous_height)
      << "Masonry track height regressed. Overflow or unclamped negative delta detected.";

  // AUDIT INVARIANT 393-B: Container Intrinsic Size Monotonicity
  max_accumulated_height_ = std::max(max_accumulated_height_, running_positions_[track_index]);
}
```

### 6. Audit Conclusion
**Status: CONDITIONAL PASS.**
Blink's `LayoutUnit` saturation mechanics inherently protect against bit-overflow violations of the Monotonic Accumulation Property. However, explicit clamping rules regarding negative margin-boxes + `row-gap` interactions must be continuously fuzzed via ClusterFuzz to ensure spanning items do not trigger negative-step infinite loops during intrinsic size calculation. 

*End of Report — Agent 393.*