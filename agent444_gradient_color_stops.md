**AUDIT REPORT: BLINK RENDERING ENGINE**
**Auditor:** Agent 444
**Target Component:** `third_party/blink/renderer/core/css/css_gradient_value.cc` & `platform/graphics/gradient.cc`
**Subject:** Gradient Color Stop Offset Monotonic Ordering Enforcement

---

### 1. Executive Summary
In compliance with the **CSS Images Module Level 3 & 4 specifications**, Blink must enforce strict monotonic ordering (specifically, *non-decreasing* order) on gradient color stop offsets before passing the data buffer to the Skia graphics backend (`SkGradientShader`). Failure to normalize these stops results in rendering artifacts or Skia assertion failures. 

This audit details the exact pipeline Blink uses to resolve, clamp, and interpolate color stop offsets to guarantee $Offset_i \le Offset_{i+1}$.

---

### 2. The Monotonicity Pipeline (CSS Specs to Blink Implementation)

When Blink parses a gradient (Linear, Radial, or Conic), color stops are ingested into a `Vector<CSSGradientColorStop>`. The offsets are initially optional and may be lengths (`px`, `em`), percentages (`%`), or `nullopt`. 

Before rendering, Blink executes a 4-stage normalization pass to enforce monotonicity:

#### Stage 1: Boundary Resolution (Terminal Stops)
Blink ensures the vector has defined start and end points.
*   **First Stop ($i = 0$):** If the offset is omitted (`nullopt`), it is explicitly assigned `0.0` (0%).
*   **Last Stop ($i = N - 1$):** If the offset is omitted, it is assigned `1.0` (100%)—or the maximum resolved length of the gradient line.

#### Stage 2: Layout-Dependent Unit Resolution
Before monotonicity can be enforced, mixed units (e.g., `linear-gradient(red 50%, blue 20px)`) must be converted into a unified scalar space (usually normalized floats `[0.0, 1.0]` based on the gradient box size via `CSSToLengthConversionData`).
*   *Audit Note:* Monotonicity **cannot** be fully resolved at parse-time if `calc()` or relative units (`px`, `rem`) are mixed with percentages. Blink defers final sorting to paint/layout time in these instances.

#### Stage 3: The Monotonic Clamp (Strict Enforcement)
For all stops with **explicitly defined** offsets, Blink iterates from $i = 1$ to $N-1$. 
*   **Rule:** If a stop’s resolved offset is less than the maximum offset encountered so far, it is clamped up to that maximum.
*   **Algorithm:**
    ```cpp
    float max_offset_so_far = stops[0].offset;
    for (size_t i = 1; i < stops.size(); ++i) {
        if (stops[i].offset.has_value()) {
            if (stops[i].offset.value() < max_offset_so_far) {
                stops[i].offset = max_offset_so_far; // Clamp to enforce monotonicity
            } else {
                max_offset_so_far = stops[i].offset.value();
            }
        }
    }
    ```
*   *Visual Result:* `linear-gradient(red 50%, blue 20%)` becomes `linear-gradient(red 50%, blue 50%)`. This creates a hard color transition (zero-width transition zone) at the 50% mark.

#### Stage 4: Implicit Offset Interpolation (Linear Distribution)
Once explicit offsets are monotonically non-decreasing, Blink resolves any remaining `nullopt` stops that sit between two explicitly defined stops.
*   **Rule:** Consecutive runs of `nullopt` offsets are evenly spaced (linearly interpolated) between the preceding explicit stop ($i_{start}$) and the succeeding explicit stop ($i_{end}$).
*   **Formula:** For a gap of $k$ unspecified stops:
    $$\Delta = \frac{Offset_{end} - Offset_{start}}{k + 1}$$
    $$Offset_{start + j} = Offset_{start} + (j \times \Delta)$$
*   *Note:* Stage 3 **must** precede Stage 4. If Stage 4 ran first, an out-of-order explicit stop would cause negative $\Delta$ values, corrupting the interpolation.

---

### 3. Skia Backend Handoff & Edge Cases

Once the Blink `Gradient` class possesses a monotonically ordered vector of `ColorStop` structs, it packs them into primitive arrays (`SkScalar pos[]` and `SkColor4f colors[]`) for Skia.

**Audit Findings on Edge Cases:**
1.  **Coincident Stops (Hard Edges):** Monotonic ordering allows $Offset_i == Offset_{i+1}$. Blink preserves their exact declaration order. Skia handles coincident stops by rendering an instantaneous color change. If three or more stops share the exact same offset (e.g., `50%, 50%, 50%`), the middle stops are effectively crushed to 0px width, and Skia transitions directly from the first to the last in that coincident group.
2.  **Transition Hints (Midpoints):** CSS allows a "color hint" (e.g., `red 10%, 30%, blue 90%`). Blink treats this as an exponential interpolation curve between the two adjacent stops. During the audit, it was verified that the hint position itself is also subject to the Stage 3 Monotonic Clamp—it cannot fall outside the bounds of its parent color stops. Blink synthesizes ~7 to 9 intermediate stops to approximate this non-linear curve for Skia, maintaining strict monotonic offsets for the synthesized stops.
3.  **Floating Point Precision (`std::nextafter`):** In older Blink revisions, coincident stops sometimes caused division-by-zero in shaders, prompting hacks where `0.00001f` was added to duplicates. Modern Blink/Skia pipelines natively support `pos[i] == pos[i+1]`, provided `pos[i] <= pos[i+1]` holds strictly against `NaN` or `-Inf` injection.

### 4. Status
**VERIFIED.** Blink's gradient offset normalization strictly adheres to W3C specifications. `DCHECK(std::is_sorted(...))` equivalents hold true prior to `SkGradientShader::MakeLinear` / `MakeRadial` / `MakeSweep` invocation. 

*Agent 444 signing off.*