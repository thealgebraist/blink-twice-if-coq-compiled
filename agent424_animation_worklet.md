**AUDIT REPORT: Blink CSS Animation Worklet – Timeline Fraction Clamping**
**Auditor:** Agent 424
**Target Component:** `third_party/blink/renderer/modules/animationworklet/` & `cc/trees/ animation_worklet_mutator`
**Subject:** Scroll/View Timeline Fraction Clamping Mechanics

---

### 1. Executive Summary
Within the Blink CSS Animation Worklet architecture, animations are frequently driven by non-monotonic timelines (specifically `ScrollTimeline` and `ViewTimeline`) rather than monotonic `DocumentTimeline`. To ensure deterministic rendering and prevent state corruption across the Main and Compositor threads, timeline progress is converted into a normalized **fraction** and strictly clamped to the `[0.0, 1.0]` range before being exposed to the Worklet’s `animate()` function as `currentTime`.

### 2. Architectural Context
The Animation Worklet decouples animation logic from the Main Thread, running JavaScript inside a dedicated `AnimationWorkletGlobalScope` on the Compositor (or a dedicated Worklet thread). 

When a `ScrollTimeline` is attached to a `WorkletAnimation`, the raw scroll offset must be translated into a `currentTime` value that the Worklet can consume. This translation relies on computing the **Timeline Fraction**.

### 3. The Fraction Calculation & Clamping Pipeline

#### 3.1. Raw Fraction Calculation
In `cc::ScrollTimeline` (the compositor representation of `blink::ScrollTimeline`), the timeline progress is calculated based on the current scroll offset relative to the resolved start and end scroll offsets:

$$\text{Raw Fraction} = \frac{\text{Current Offset} - \text{Start Offset}}{\text{End Offset} - \text{Start Offset}}$$

#### 3.2. The Clamping Mechanism
Physical scroll offsets can exceed the defined `[Start Offset, End Offset]` bounds. This occurs due to:
1. **Overscroll / Elastic Bounce:** Common on macOS, iOS, and Android.
2. **Sub-pixel/Layout Rounding:** Discrepancies between Blink layout units and CC layer bounds.
3. **Timeline Range Offsets:** Custom `scroll-offsets` (e.g., `[100px, 500px]`) where the user scrolls to `50px` or `600px`.

To handle this, the compositor enforces strict clamping:

```cpp
// Conceptual representation in cc/animation/scroll_timeline.cc
double progress = (current_offset - start_offset) / (end_offset - start_offset);
double clamped_fraction = std::clamp(progress, 0.0, 1.0);
```

*   **Underflow (< 0.0):** If `Current Offset < Start Offset`, the fraction is clamped to `0.0`.
*   **Overflow (> 1.0):** If `Current Offset > End Offset`, the fraction is clamped to `1.0`.

#### 3.3. Mapping to Worklet `currentTime`
The clamped fraction is then multiplied by the timeline's effective `time_range` (or an internal `kScrollTimelineDuration` scalar in newer CSS Scroll-Driven Animation specs where `currentTime` is represented as a `CSSNumericValue` percentage).

$$\text{Worklet } currentTime = \text{clamped\_fraction} \times \text{Duration}$$

### 4. Edge Cases & Special States

During the audit of the clamping logic, several critical edge cases in the Blink/CC implementation must be accounted for:

*   **Zero-Length Scroll Range (`Start Offset == End Offset`):**
    *   *Condition:* The scrollable container cannot scroll, or the timeline range collapses to zero.
    *   *Resolution:* Division by zero is avoided. Depending on whether the current offset is before or at/after the collapsed point, the fraction is resolved to `0.0` or `1.0` (or `NaN` -> `Inactive` if the scroller is not laid out).
*   **Inactive Timelines (`std::nullopt` / `null`):**
    *   *Condition:* The scroll source is `display: none`, not a scroll container, or layout is not yet complete.
    *   *Resolution:* Clamping is bypassed entirely. The timeline returns an `unresolved` (`null` in JS) `currentTime`. The Worklet’s `animate()` function may not be invoked, or must handle `NaN`/`null`.
*   **Boundary Exclusivity (`1.0` vs `0.999...`):**
    *   In standard Web Animations, reaching `1.0` (100% progress) triggers the `after` phase, where the `fill-mode` (`forwards`, `none`) dictates whether the effect applies.
    *   If clamped strictly to `1.0`, an animation with `fill: none` would abruptly drop its effect at the exact end of the scroll container. Blink's timing conversion (`AnimationEffect::CalculateTransformedProgress`) interacts with the clamped timeline fraction to respect `fill-mode` semantics when the Worklet returns a `localTime` equal to the effect's duration.

### 5. Security & Stability Implications (Audit Findings)

1.  **NaN / Infinity Propagation Prevention:** 
    By clamping the fraction at the `cc::ScrollTimeline` level before passing `AnimationWorkletInput` to the `AnimationWorkletMutator`, Blink prevents `Infinity` or `-Infinity` from entering the V8 isolate. However, the Worklet *itself* can still assign `effect.localTime = NaN` or out-of-bounds values, which requires secondary validation in `WorkletAnimationEffect`.
2.  **Overscroll Jitter:**
    Because the fraction is clamped to `[0.0, 1.0]`, developers inside the Animation Worklet **cannot** natively detect overscroll (bounce) effects via `currentTime` alone, as the value flatlines at `0` or `timeRange`. 
3.  **Thread Synchronization:**
    Clamping logic must be strictly identical between `blink::ScrollTimeline` (Main) and `cc::ScrollTimeline` (Compositor). Any floating-point divergence in `std::clamp` or offset resolution between threads will cause visual snapping when a main-thread commit overwrites compositor-thread scroll offsets.

**Status:** Clamping mechanics verified. Logic resides primarily within `cc/animation/scroll_timeline.cc` (`CurrentTime`) and `third_party/blink/renderer/core/animation/scroll_timeline.cc` (`CalculateOffsets`). **Audit Complete.**