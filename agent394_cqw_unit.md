**AUDIT REPORT: Blink CSS Engine – `cqw` Unit Resolution**  
**Auditor:** Agent 394  
**Component:** `third_party/blink/renderer/core/css/`  
**Subject:** Mathematical invariants of `cqw` (Container Query Width) resolution: Non-Negativity and Linearity.

---

### 1. Executive Summary
The `cqw` unit represents 1% of the query container's inline (or horizontal physical) size. Within the Blink rendering engine, `cqw` resolution occurs during the `CSSToLengthConversionData` pipeline. The resolution strictly enforces **non-negativity** via layout clamping and preserves **linearity** prior to layout-unit quantization.

---

### 2. Non-Negativity Analysis

By CSS specification (CSS Values and Units Level 4 / CSS Containment Level 3), container dimensions cannot be negative. However, a `cqw` unit *value* itself can be negative (e.g., `margin-left: -5cqw`).

#### A. Base Container Size Clamping ($W_c \ge 0$)
1. **Box Model Invariant:** A query container’s content box width ($W_c$) is derived from its `LayoutBox` physical fragments during the ConstraintSpace builder phase. 
2. **Clamping Mechanism:** In Blink’s layout engine (LayoutNG), content-box widths are calculated as `max(0, border_box_width - borders - paddings)`. Even under extreme sub-pixel starvation or malformed CSS, `LayoutUnit` values representing physical dimensions are clamped at `LayoutUnit(0)`.
3. **Fallback Non-Negativity:** If no eligible ancestor defines a query container (`container-type: size` or `inline-size`), Blink falls back to the **Small Viewport Width (`svw`)**. The viewport dimensions managed by `ViewportSize` in `CSSToLengthConversionData` are strictly unsigned/clamped to $\ge 0$.

#### B. Sign Preservation of the CSS Value
While the base unit $1\text{cqw} = \frac{W_c}{100}$ is strictly $\ge 0$:
* If a specified CSS value $v < 0$, the resolved length $L(v) = v \times 1\text{cqw} \le 0$.
* If the target CSS property disallows negative lengths (e.g., `width`, `padding-left`), clamping is deferred to `CSSPrimitiveValue::ConvertToLength` via the `ValueRange::kNonNegative` flag, **not** during the `cqw` unit resolution itself. This guarantees `calc(-5cqw + 100px)` evaluates correctly before property-specific range clamping.

---

### 3. Linearity Analysis

Resolution of `cqw` must behave as a linear map $f: \mathbb{R} \times \mathbb{R}_{\ge 0} \to \mathbb{R}$, defined as:
$$L(v, W_c) = v \cdot \left(\frac{W_c}{100}\right)$$

#### A. Scalar Linearity (Fixed $W_c$, Variable $v$)
Within `CSSToLengthConversionData::ContainerSizes`, the container width is cached as a ` std::optional<double>` or `LayoutUnit`. 
* **Additivity:** $L(v_1 + v_2, W_c) = L(v_1, W_c) + L(v_2, W_c)$
* **Homogeneity:** $L(c \cdot v, W_c) = c \cdot L(v, W_c)$

Blink preserves this by resolving `cqw` in double-precision floating-point arithmetic (`double`) inside `CSSPrimitiveValue` and `CSSMathExpressionNode` (for `calc()`). Linearity is strictly maintained throughout the CSS Value tree evaluation.

#### B. Container-Width Linearity (Fixed $v$, Variable $W_c$)
As the container width $W_c$ scales, the resolved pixel value scales linearly:
$$L(v, \alpha W_c) = \alpha L(v, W_c)$$
Blink achieves this by invalidating style/layout when the container's `PhysicalFragment` size changes during the `ContainerQueryEvaluator` pass, feeding the new linear base into `CSSToLengthConversionData`.

#### C. Deviations from Strict Mathematical Linearity (Quantization)
Strict linearity breaks at the boundary between CSS Value resolution and LayoutNG consumption due to **fixed-point quantization**:
1. **`LayoutUnit` Conversion:** Blink converts the resolved `double` into a `LayoutUnit` (which uses 1/64th of a pixel precision, `kFixedPointDenominator = 64`).
2. **Rounding Error:** 
   $$\text{LayoutUnit}(L(v_1, W_c)) + \text{LayoutUnit}(L(v_2, W_c)) \neq \text{LayoutUnit}(L(v_1 + v_2, W_c))$$
   This deviation is bounded by $\epsilon < \frac{1}{64}\text{px}$ (`0.015625px`).
3. **Sub-pixel Accumulation in `calc()`:** Inside a `calc()` expression (e.g., `calc(10cqw + 15cqw)`), Blink evaluates nodes in `double` precision *before* clamping to `LayoutUnit`, preserving linearity internal to the math expression.

---

### 4. Audit Verdict
* **Non-Negativity:** **PASS.** Base `1cqw` scalar is guaranteed $\ge 0$ via LayoutNG box clamping and viewport fallback invariants.
* **Linearity:** **PASS (with expected quantization bounds).** Floating-point resolution in `CSSToLengthConversionData` is strictly linear; non-linearity is isolated to final `1/64px` `LayoutUnit` snapping.