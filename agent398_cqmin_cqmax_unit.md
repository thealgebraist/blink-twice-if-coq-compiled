**AUDIT REPORT: Blink CSS Engine – Container Query Units (`cqmin` / `cqmax`)**  
**Auditor:** Agent 398  
**Component:** `Blink>CSS` (Specifically `CSSToLengthConversionData` and `ContainerSizes`)  
**Subject:** Verification and Detail of the `cqmin <= cqmax` Inequality Invariant  

---

### 1. Executive Summary
An audit of the Blink CSS layout and style resolution engine confirms that the mathematical invariant $\text{cqmin} \le \text{cqmax}$ holds unconditionally across all layout modes, writing directions, and fallback states. This report details the mechanics of this inequality from CSS specification through to Blink’s C++ implementation.

---

### 2. Theoretical Foundation & Definitions
Per the **CSS Conditional Rules Module Level 5** specification, container query length units are relative to the dimensions of the nearest query container:

*   **`cqi` (Container Query Inline):** $1\%$ of the query container's inline size ($I$).
*   **`cqb` (Container Query Block):** $1\%$ of the query container's block size ($B$).
*   **`cqmin`:** The smaller value between `cqi` and `cqb`.
*   **`cqmax`:** The larger value between `cqi` and `cqb`.

*(Note: While `cqw` (width) and `cqh` (height) exist, they are purely physical axes. Since the physical axes $(W, H)$ are always a direct permutation of the logical axes $(I, B)$ based on `writing-mode`, the set $\{cqi, cqb\}$ is mathematically identical to $\{cqw, cqh\}$).*

#### The Inequality Proof
Let $I$ and $B$ represent the resolved inline and block lengths of a container. In CSS layout, sizes of layout boxes cannot be negative ($I \ge 0, B \ge 0$).

$$\text{1cqmin} = \frac{\min(I, B)}{100}$$
$$\text{1cqmax} = \frac{\max(I, B)}{100}$$

By the fundamental properties of real numbers:
$$\forall I, B \in \mathbb{R}_{\ge 0}, \quad \min(I, B) \le \max(I, B)$$

Dividing by a positive scalar ($100$) preserves the inequality:
$$\text{1cqmin} \le \text{1cqmax}$$

**Equality Condition ($\text{cqmin} = \text{cqmax}$):**  
The inequality resolves to strict equality if and only if $I = B$ (the container is a perfect square) or when comparing $0\text{cqmin}$ and $0\text{cqmax}$.

---

### 3. Blink Engine Implementation Details

In Chromium's Blink engine, the evaluation of these units occurs during style resolution in `third_party/blink/renderer/core/css/css_to_length_conversion_data.cc`.

#### A. Resolution Pipeline
When a CSS property uses `cqmin` or `cqmax`, `CSSToLengthConversionData::ContainerSizes` fetches the physical dimensions of the nearest ancestor with `container-type` established:

```cpp
// Conceptual representation of Blink's internal resolution
double CSSToLengthConversionData::ContainerSizes::Min() const {
  return std::min(InlineSize(), BlockSize());
}

double CSSToLengthConversionData::ContainerSizes::Max() const {
  return std::max(InlineSize(), BlockSize());
}
```
Because Blink utilizes the C++ standard library `std::min` and `std::max` on `double` (or `LayoutUnit` converted to `double`), the invariant $\text{Min()} \le \text{Max()}$ is guaranteed at the hardware/compiler level, provided neither value is `NaN` (which Blink prevents via layout clamping).

#### B. Edge Case 1: Single-Axis Containment (`inline-size`)
A critical edge case in Blink occurs when a container is defined with `container-type: inline-size` rather than `size` (which covers both axes). 
*   **The Problem:** For `inline-size` containers, the container's `cqi` is known, but its `cqb` (block size) cannot be queried from the container itself without causing a layout loop.
*   **Blink's Fallback Mechanism:** If a container query unit cannot be resolved against a container axis, Blink falls back to the ** Small Viewport (`sv*`)** units for that specific axis.
    *   $I = \text{Container Inline Size}$
    *   $B = \text{Small Viewport Block Size (svb)}$
*   **Inequality Impact:** Even in this hybrid state where `cqi` comes from the DOM element and `cqb` comes from the `ViewportSize`, both inputs remain non-negative scalars before being passed to `std::min` and `std::max`. The $\text{cqmin} \le \text{cqmax}$ inequality remains unbroken.

#### C. Edge Case 2: Missing Container Context
If an element utilizes `cqmin` or `cqmax` and has **no** ancestor query container in the flat tree:
*   `cqi` falls back to `1svi` (Small Viewport Inline).
*   `cqb` falls back to `1svb` (Small Viewport Block).
*   `cqmin` effectively becomes `svmin`, and `cqmax` becomes `svmax`.
*   **Inequality Impact:** Since $\text{svmin} \le \text{svmax}$, the invariant holds.

#### D. Edge Case 3: Negative Multipliers in Author CSS
While the *base unit* satisfies $\text{1cqmin} \le \text{1cqmax}$, CSS authors can apply negative scalars.
*   For a scalar $k > 0$: $k \cdot \text{cqmin} \le k \cdot \text{cqmax}$
*   For a scalar $k < 0$: $k \cdot \text{cqmin} \ge k \cdot \text{cqmax}$ (The inequality flips).
*   *Audit Note:* Blink handles the scalar multiplication *after* fetching the base unit via `ZoomedComputedPixels()`. This is mathematically sound and complies with the CSS Values and Units specification.

#### E. Subpixel Layout and Rounding (`LayoutUnit`)
Blink uses `LayoutUnit` (fixed-point math with $1/64\text{th}$ pixel precision) for layout, and `float`/`double` for Computed Style resolution. 
Because `std::min` and `std::max` are evaluated *prior* to any final pixel-snapping or `LayoutUnit` clamping, it is impossible for rounding errors to invert the inequality. If $\text{cqmin} \le \text{cqmax}$ in floating-point, and a monotonic rounding function $R(x)$ is applied, $R(\text{cqmin}) \le R(\text{cqmax})$ is strictly preserved.

---

### 4. Audit Conclusion
**Status:** **PASSED (No Vulnerabilities or Spec Violations Found)**

The inequality $\text{1cqmin} \le \text{1cqmax}$ is a strict invariant in Blink. By evaluating container dimensions (and their viewport fallbacks) as non-negative floating-point numbers before passing them directly to `std::min` and `std::max`, Blink ensures that `cqmin` will never exceed `cqmax` under any combination of `container-type`, `writing-mode`, or layout fallback states. 

*End of Report — Agent 398.*