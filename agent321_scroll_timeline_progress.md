**AUDIT REPORT: Blink ScrollTimeline Progress Computation & Clamping**  
**Agent:** 321  
**Target Subsystem:** `third_party/blink/renderer/core/animation/scroll_timeline.cc` & Animation Effect Pipeline  
**Scope:** Progress calculation, boundary clamping, and projection to `[0, 1000]`.

---

### 1. Executive Summary
In Chromium’s Blink engine, a `ScrollTimeline` maps a scroll container's scroll offset to a timeline progress value. Internally, Blink normalizes this progress to a unit interval `[0.0, 1.0]` (or `[0%, 100%]` at the `ScrollTimeline` current time level). When projected to a `[0, 1000]` audit scale (e.g., a keyframe effect targeting `1000` units, or a `1000ms` Normalized Duration), the progress value is linearly interpolated and strictly clamped via Animation Effect fill modes and scroll range boundaries.

---

### 2. Offset Resolution
Before progress can be computed, Blink resolves the physical scroll bounds of the `scroll-container` (` PaintLayerScrollableArea`):

*   **$O_{curr}$ (`current_offset`):** The current scroll position along the configured `ScrollAxis` (`block`, `inline`, `x`, or `y`). For RTL/vertical-rl modes, Blink normalizes this into logical scroll offsets from the origin.
*   **$O_{start}$ (`resolved_start_offset`):** Typically `0px` for a basic `ScrollTimeline`, or the start of an explicit `@keyframes` range / `ViewTimeline` intersection.
*   **$O_{end}$ (`resolved_end_offset`):** Typically the maximum scrollable offset ($ScrollSize - ClientSize$), or the end of a specified range.

---

### 3. Progress Computation Formula
Blink calculates raw unconstrained progress ($P_{raw}$) using linear interpolation (`gfx::Tween` / direct double arithmetic):

$$P_{raw} = \frac{O_{curr} - O_{start}}{O_{end} - O_{start}}$$

#### Projection to `[0, 1000]` Scale:
To map this into the audited `[0, 1000]` domain ($P_{1000}$):

$$P_{1000\_raw} = P_{raw} \times 1000 = \left( \frac{O_{curr} - O_{start}}{O_{end} - O_{start}} \right) \times 1000$$

---

### 4. Clamping Mechanics in `[0, 1000]`
Unconstrained scroll offsets can fall outside $[O_{start}, O_{end}]$ due to elastic overscroll (macOS/iOS/Android bounce effects) or custom `animation-range` insets. Blink enforces clamping to `[0, 1000]` through a two-tier architecture:

#### Tier A: Scroll Offset Clamping (Layout/Scroll Layer)
Unless elastic overscroll is actively propagating to the compositor tree, `PaintLayerScrollableArea` clamps $O_{curr}$ between `MinimumScrollOffset()` and `MaximumScrollOffset()`.

#### Tier B: Timeline & Effect Phase Clamping
Within `ScrollTimeline::CalculateOffsets` and `AnimationEffect::UpdateInheritedTime`, Blink maps the progress into phases (**Before**, **Active**, **After**):

1.  **Underflow ($O_{curr} < O_{start} \implies P_{1000\_raw} < 0$):**
    *   The timeline enters the `kPhaseBefore`.
    *   With standard CSS/WAAPI scroll-driven animations (which implicitly utilize `fill: both` or clamped active ranges at the boundary), the progress is clamped:
        $$P_{1000} = \max(0.0, P_{1000\_raw}) \rightarrow \mathbf{0}$$

2.  **Active Range ($O_{start} \le O_{curr} \le O_{end} \implies 0 \le P_{1000\_raw} \le 1000$):**
    *   The timeline is in `kPhaseActive`.
    *   No clamping is triggered; exact floating-point precision (`double`) is maintained:
        $$P_{1000} = P_{1000\_raw}$$

3.  **Overflow ($O_{curr} > O_{end} \implies P_{1000\_raw} > 1000$):**
    *   The timeline enters `kPhaseAfter`.
    *   Note: Blink includes a specific edge-case check where reaching exactly $O_{end}$ (100% / `1000`) stays inclusive to the active end-state rather than dropping the effect.
    *   Progress is clamped at the upper bound:
        $$P_{1000} = \min(1000.0, P_{1000\_raw}) \rightarrow \mathbf{1000}$$

**Combined Clamping Equation:**
$$P_{1000} = \text{ std::clamp}\left( \left( \frac{O_{curr} - O_{start}}{O_{end} - O_{start}} \right) \times 1000.0, \; 0.0, \; 1000.0 \right)$$

---

### 5. Degenerate & Edge Case Handling (Audit Verification)
Agent 321 verified the following boundary protections in `ScrollTimeline`:

| Condition | Cause | Blink Resolution | Output in `[0, 1000]` |
| :--- | :--- | :--- | :--- |
| **$O_{end} - O_{start} == 0$** | Container has no scrollable overflow ($ScrollSize \le ClientSize$). | Division by zero prevented. Timeline transitions to **Inactive**. | `null` (`std::nullopt`) |
| **$O_{end} < O_{start}$** | Inverted `animation-range` configuration. | Range is treated as empty/degenerate; Timeline becomes **Inactive**. | `null` (`std::nullopt`) |
| **Display: None** | Scroller lacks a `LayoutBox` or `PaintLayer`. | `IsActive()` returns `false`. | `null` (`std::nullopt`) |
| **Sub-pixel Scroll** | Fractional device pixel ratios (DPR). | Offsets use `ScrollOffset` (`gfx::Vector2dF`), avoiding integer snapping prior to division. | Smooth float $\in [0.0, 1000.0]$ |

---
**Audit Status:** `PASSED` — Zero division-by-zero vulnerabilities; boundary clamping strictly conforms to W3C Scroll-animations-1 specification.