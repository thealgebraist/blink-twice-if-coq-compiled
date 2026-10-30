**AUDIT LOG: AGENT 414**  
**SUBSYSTEM:** Chromium / Blink Rendering Engine (`core/scroll`, `core/paint/ paint_layer_scrollable_area.cc`)  
**SUBJECT:** Scroll Offset Clamping: Bounds Enforcement & Idempotency Analysis  

---

### 1. Executive Summary
This audit evaluates the mathematical and architectural integrity of Blink’s scroll offset clamping mechanism, primarily managed by `ScrollableArea::ClampScrollOffset` and `PaintLayerScrollableArea`. The objective is to verify that arbitrary scroll offsets are strictly constrained within valid layout boundaries and that the clamping operation is strictly idempotent across layout cycles, fractional scaling, and writing modes.

---

### 2. Bounds Clamping Mechanics

In Blink, a scroll offset represents the translation of the scrolled content relative to the scroll container's origin. Clamping ensures the viewport never exposes out-of-bounds areas (unless explicitly handled by overscroll/elastic effects at the compositor level).

#### 2.1. The Clamping Formula
At the core of `ScrollableArea`, the valid scroll range is defined by `[MinimumScrollOffset, MaximumScrollOffset]`. For a given unconstrained `ScrollOffset` $O$, the clamped offset $O_{clamped}$ is computed per axis as:

$$O_{clamped} = \min(\max(O, O_{min}), O_{max})$$

In Blink's C++ implementation, this is executed via `gfx::Vector2dF` clamping methods:
```cpp
ScrollOffset PaintLayerScrollableArea::ClampScrollOffset(const ScrollOffset& offset) const {
  return offset.ClampedTo(MinimumScrollOffset(), MaximumScrollOffset());
}
```

#### 2.2. Boundary Definitions
*   **Minimum Scroll Offset ($O_{min}$):** 
    *   In standard Left-to-Right (LTR) and Top-to-Bottom writing modes, $O_{min} = (0, 0)$.
    *   In Right-to-Left (RTL) or `flex-direction: column-reverse` scenarios, the origin shifts. Depending on whether Blink is using `ScrollOrigin` offsets or physical offsets, $O_{min}$ can be negative: 
        $$O_{min} = \min(0, \text{ClientSize} - \text{ScrollSize})$$
*   **Maximum Scroll Offset ($O_{max}$):** 
    *   Defined as the total scrollable overflow dimension minus the visible client dimension (excluding scrollbars):
        $$O_{max} = \max(0, \text{ScrollSize} - \text{ClientSize})$$

#### 2.3. Edge Cases in Bounds Calculation
*   **Underflow ($\text{ScrollSize} < \text{ClientSize}$):** If the content is smaller than the container, $\text{ScrollSize} - \text{ClientSize}$ yields a negative value. If `MinimumScrollOffset()` is $(0,0)$ and `MaximumScrollOffset()` were allowed to be negative, the `min(max())` operation would invert. Blink prevents this by clamping $O_{max}$ to a floor of `0` (in standard origins) before applying it to the scroll offset, ensuring $O_{min} \le O_{max}$ is strictly maintained.
*   **Subpixel Layout & Fractional Scroll Offsets:** When ` fractional_scroll_offsets` are enabled, bounds are retained as `float` (`gfx::Vector2dF`). When disabled, `MaximumScrollOffset()` is floored/rounded to `int` via `LayoutUnit` conversions, which can introduce a $\le 1\text{px}$ discrepancy between the compositor (`cc`) and the main thread (`blink`).

---

### 3. Idempotency Analysis

**Definition:** An operation $f$ is idempotent if $\forall x, f(f(x)) = f(x)$.  
In the context of Blink: `ClampScrollOffset(ClampScrollOffset(offset)) == ClampScrollOffset(offset)`.

#### 3.1. Mathematical Idempotency
Provided that $O_{min} \le O_{max}$ holds true (which is guaranteed by the underflow protection in `MaximumScrollOffset()`), the interval $[O_{min}, O_{max}]$ is valid and non-empty. A projection onto a closed convex set (an interval) is inherently idempotent. Once $O_{clamped} \in [O_{min}, O_{max}]$, subsequent applications of `ClampScrollOffset` will evaluate $\max(O_{clamped}, O_{min}) = O_{clamped}$ and $\min(O_{clamped}, O_{max}) = O_{clamped}$.

#### 3.2. Architectural Threats to Idempotency (State-Dependent Failures)
While the math is idempotent in isolation, **systemic non-idempotency** can occur in Blink if applying the clamped scroll offset mutates the layout state used to calculate $O_{min}$ and $O_{max}$. 

Agent 414 identifies three primary vectors where idempotency is threatened during a lifecycle update:

1.  **`overflow: auto` Scrollbar Oscillation:**
    *   **Scenario:** Clamping an offset triggers a layout update that causes scrollbars to appear or disappear, altering `ClientSize`.
    *   **Impact:** $O_{max}$ changes *after* the first clamp. A second call to `ClampScrollOffset` immediately following layout will yield a different result: $f_2(f_1(x)) \neq f_1(x)$.
    *   **Mitigation:** Blink handles this via `PaintLayerScrollableArea::UpdateAfterLayout()`, freezing scrollbar state during specific layout passes or running a multi-pass layout stabilization loop before finalizing the clamp.

2.  **Scroll Anchoring Interference:**
    *   **Scenario:** Clamping occurs during DOM mutation. `ScrollAnchor` attempts to adjust the scroll offset to prevent visual jumps.
    *   **Impact:** If clamping triggers an anchor adjustment, which in turn requires re-clamping, an infinite loop or jitter can occur.
    *   **Mitigation:** Scroll anchoring adjustments are explicitly bypassed or finalized *before* the authoritative clamp in the lifecycle (`kInScrollAnchorAdjustment` state flags).

3.  **Floating-Point Precision & Snapping (Compositor Sync):**
    *   **Scenario:** Main thread clamps a float offset, snaps it to physical pixels (device scale factor), and sends it to the compositor. The compositor clamps it against its own `cc::ScrollNode` bounds and returns a delta.
    *   **Impact:** `std::floor` or `LayoutUnit::FromFloatRound` applied *inside* or * alongside* the clamping pipeline can break idempotency if the conversion is asymmetric (e.g., `FloatToLayoutUnit` followed by `LayoutUnitToFloat` losing precision outside the IEEE 754 mantissa limits).
    *   **Mitigation:** Blink separates *clamping* from *pixel snapping*. `ClampScrollOffset` operates purely in the `ScrollOffset` (`gfx::Vector2dF`) domain without internal type-casting.

---

### 4. Audit Verdict

*   **Bounds Enforcement:** **PASS.** `MinimumScrollOffset` and `MaximumScrollOffset` correctly account for writing modes, origins, and content underflow, maintaining the invariant $O_{min} \le O_{max}$.
*   **Pure Function Idempotency:** **PASS.** `ClampScrollOffset` is a pure mathematical projection with no side effects on the `ScrollableArea` state.
*   **Lifecycle Idempotency:** **CONDITIONAL PASS.** Relies heavily on `PaintLayerScrollableArea::PendingScrollAnchorAdjustment` and `ScrollbarManager` stabilization during `UpdateAfterLayout`. Any regression bypassing the layout-Before-Clamp ordering will violate state idempotency.

**END OF AUDIT - AGENT 414**