**AUDIT REPORT: Blink Rendering Engine**
**Auditor:** Agent 307
**Component:** CSS Easing Functions (`gfx::LinearEasingPoint` / `cc::LinearTimingFunction`)
**Subject:** Piecewise Linear Interpolation & Monotonicity Enforcement

---

### 1. Executive Summary
The `linear()` easing function in Blink allows developers to approximate complex animations using piecewise linear interpolation over a series of stop points. While the **output progress ($y$)** can move in any direction (allowing bounce/elastic effects), the **input progress ($x$)**—representing normalized time—must remain **strictly non-decreasing (monotonically increasing)** across the control points. 

This audit details the mathematical interpolation model, canonicalization rules, and edge-case handling used by Blink to enforce input monotonicity as defined by the CSS Easing Functions Level 2 specification.

---

### 2. Data Representation
In Blink, a `linear()` function is parsed from CSS into a vector of control points:
$$P = \{ (x_0, y_0), (x_1, y_1), \dots, (x_n, y_n) \}$$

*   **$x_i$ (Input/Time):** Normalized time domain, typically $[0, 1]$, though Blink must evaluate inputs outside this range if chained with other timing functions.
*   **$y_i$ (Output/Progression):** Unbounded value domain $(-\infty, \infty)$.

---

### 3. Input Monotonicity Enforcement (Canonicalization)
Before interpolation can occur on the compositor thread, Blink’s CSS parser (`css_parsing_utils`) canonicalizes the point list to guarantee input monotonicity ($x_0 \le x_1 \le \dots \le x_n$).

1.  **Boundary Anchoring:**
    *   If $x_0$ is omitted, it is assigned $0.0$.
    *   If $x_n$ is omitted, it is assigned $1.0$.
2.  **Clamping for Monotonicity:**
    *   If a developer specifies an input percentage $x_i$ that is less than any preceding explicitly specified input $x_j$ (where $j < i$), Blink **clamps** $x_i$ to maintain monotonicity:
        $$x_i = \max(x_i, x_{i-1})$$
    *   *Audit Note:* This prevents time-travel (evaluating multiple segments for a single timestamp) and avoids division-by-zero traps caused by negative slopes in the time domain.
3.  **Null-Input Resolution (Even Distribution):**
    *   For any contiguous run of points with omitted $x$ values between two defined points $x_a$ and $x_b$, Blink interpolates their $x$ coordinates linearly:
        $$x_i = x_a + \frac{i - a}{b - a} (x_b - x_a)$$
    *   Because $x_b \ge x_a$ is guaranteed by Step 2, the generated $x_i$ values are inherently monotonic.

---

### 4. Piecewise Linear Interpolation Mechanics
During animation ticks, the function `Evaluate(double t)` is called for a given input time $t$.

#### A. Segment Identification
Because $X$ is monotonically increasing, Blink uses binary search (`std::upper_bound`) to find the active segment $[P_i, P_{i+1}]$ where $x_i \le t \le x_{i+1}$ in $O(\log n)$ time.

#### B. Standard Interpolation
For a valid segment where $x_{i+1} > x_i$, the output $Y(t)$ is calculated via standard linear interpolation (`gfx::Tween`):
$$\alpha = \frac{t - x_i}{x_{i+1} - x_i}$$
$$Y(t) = y_i + \alpha (y_{i+1} - y_i)$$

#### C. Non-Strict Monotonicity Edge Case (Coincident Points)
Input monotonicity is **non-strict** ($x_i \le x_{i+1}$). Developers or clamping rules can create step functions where $x_i = x_{i+1}$.
*   **Risk:** $\frac{t - x_i}{x_{i+1} - x_i}$ results in $\frac{0}{0}$ (`NaN`).
*   **Blink Mitigation:** If $x_i == x_{i+1}$, Blink bypasses interpolation. Depending on the playback direction (or phase), it resolves immediately to $y_{i+1}$ (the rightmost defined point at that timestamp).

#### D. Extrapolation ($t < x_0$ or $t > x_n$)
If an upstream timing function pushes input $t$ outside $[0, 1]$, or if the author explicitly set $x_0 > 0$ or $x_n < 1$:
*    Blink does not clamp $t$. It extends the slope of the first segment (if $t < x_0$) or the last segment (if $t > x_n$) infinitely.
*   If the boundary segment has coincident $x$ values ($x_0 = x_1$), the slope is infinite; Blink falls back to flat extrapolation ($Y(t) = y_0$).

---

### 5. Output Non-Monotonicity
While **Input ($x$)** is strictly monotonic, **Output ($y$)** is explicitly **non-monotonic** by design. 
*   A segment where $y_{i+1} < y_i$ results in a negative slope, reversing the animation progress.
*   **Auditor Warning for Compositor:** Because $Y(t)$ is non-monotonic and can exceed $[0.0, 1.0]$, property-specific clamping (e.g., `opacity` clamped to $[0, 1]$) must occur *after* the easing evaluation, never during the `LinearTimingFunction` calculation itself.

---

### 6. Audit Verdict
**STATUS: COMPLIANT**
Blink’s implementation of `linear()` correctly enforces non-decreasing monotonicity in the time domain at parse time. The runtime evaluator safely handles coincident control points (vertical slopes) without `NaN` propagation and maintains $O(\log n)$ lookup efficiency.

*End of Report — Agent 307*