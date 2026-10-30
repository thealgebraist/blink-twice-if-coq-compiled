**AUDIT REPORT: Blink ScrollTimeline Inactive State (Scroll Range $\le 0$)**
**Agent:** 328
**Component:** `third_party/blink/renderer/core/animation/scroll_timeline.cc` (and related cc/animation structures)
**Specification:** CSS Scroll-driven Animations (ScrollTimeline)

---

### 1. Executive Summary
Per the W3C Scroll-driven Animations specification and Chromium’s Blink implementation, a `ScrollTimeline` transitions to an **inactive state** whenever its effective scroll range (maximum scroll offset) is less than or equal to zero ($\le 0$). In this state, the timeline possesses no valid progress, and its `currentTime` resolves to `null` (internally represented as `std::nullopt`).

### 2. Trigger Conditions for `range <= 0`
During the `ScrollTimeline::CalculateOffsets` phase (executed during the Compositing/PrePaint lifecycle steps), the maximum scroll offset is computed as:
$$\text{max\_offset} = \text{scroll\_size} - \text{client\_size}$$

A range of $\le 0$ occurs under the following conditions:
*   **No Overflow (`range == 0`):** The scroll container's content fits entirely within the layout viewport/client area (`scrollHeight == clientHeight` for block/vertical, or `scrollWidth == clientWidth` for inline/horizontal).
*   **Sub-pixel/Negative Rounding (`range < 0`):** Rare layout edge cases involving negative margins, collapsed flex/grid bounds, or sub-pixel rounding discrepancies prior to clamping.
*   **Unrendered/Detached Boxes:** The `LayoutBox` is `display: none` or disconnected from the DOM, yielding `0` for both scroll and client dimensions.

### 3. Blink Internal State Detail

When `max_offset <= 0` is detected, Blink updates the `ScrollTimeline`'s internal state snapshot (`TimelineState`) during `ScrollTimeline::SnapshotState()` as follows:

#### A. `ScrollTimeline` (Main Thread)
1.  **Offset Resolution:** `ResolveScrollOffsets()` fails to produce valid start/end boundaries and returns `false` (or empty offsets).
2.  **Phase:** `TimelinePhase::kInactive`
3.  **Current Time:** `std::nullopt` (Exposed to V8/JS APIs as `null`).
4.  **Scroll Offsets:** `scroll_offsets_` is cleared (`std::nullopt`).

#### B. `Animation` Impact
When the attached `ScrollTimeline` goes inactive:
*   **Play State:** If the animation is otherwise running, it remains technically "running" or "idle" depending on prior state, but produces **no visual effect** unless dictated by fill modes, which generally do not apply when a timeline is inactive.
*   **CurrentTime / Progress:** `animation.currentTime` returns `null`.
*   **Effect Application:** The `KeyframeEffect` is suppressed. The animated properties fall back to their base computed styles during the Style Recalc phase.

#### C. `cc::ScrollTimeline` (Compositor Thread)
During the `PushPropertiesTo` synchronization step in the Paint/Commit lifecycle:
*   Blink pushes an empty `scroll_offsets` structure (`std::nullopt`) to the compositor thread's `cc::ScrollTimeline`.
*   `cc::ScrollTimeline::IsActive()` evaluates to `false` on the impl thread.
*   The compositor skips ticking the associated `cc::Animation`, preventing divide-by-zero FPEs (Floating Point Exceptions) when calculating normalized progress ($\frac{\text{current\_offset}}{\text{max\_offset}}$).

### 4. Relevant Code Path (Blink Reference)

```cpp
// Conceptual representation of third_party/blink/renderer/core/animation/scroll_timeline.cc

ScrollTimeline::TimelineState ScrollTimeline::ComputeTimelineState() const {
  TimelineState state;
  // ... [Checks for ResolvedSource and LayoutBox existence] ...

   PaintLayerScrollableArea* scrollable_area = ...;
  
  // Calculate scroll range
  double current_offset = ...;
  double max_offset = ...; // scroll_dimensions - client_dimensions

  // AUDIT TARGET: Range <= 0 check
  if (max_offset <= 0.0) {
    // Timeline defaults to inactive state:
    // state.phase = TimelinePhase::kInactive;
    // state.current_time = std::nullopt;
    // state.scroll_offsets = std::nullopt;
    return state; 
  }

  // If > 0, proceed to calculate active current_time and offsets...
}
```

### 5. Edge Cases & Audit Notes
*   **Dynamic Resizing:** If a `ResizeObserver` or layout mutation reduces content size such that `max_offset` drops from $>0$ to $\le 0$, the timeline becomes inactive on the **next** animation frame (specifically, during the next `UpdateSnapshot()` call).
*   **`overflow: hidden`:** A container with `overflow: hidden` *can* still have a `range > 0` if its content overflows, meaning the timeline remains **active** (programmable via `scrollTop`), whereas `overflow: visible` or `overflow: clip` forces the scrollable area to not exist, defaulting to inactive.

**Status:** Verified compliant with CSS Scroll-driven Animations Level 1 Specification. End of report.