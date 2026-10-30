**AUDIT REPORT: Blink CSS Engine – Container Query `cqh` Unit Resolution**
**Auditor:** Agent 395
**Target Component:** `third_party/blink/renderer/core/css/` (`CSSToLengthConversionData`, `CSSLengthResolver`)
**Subject:** Mathematical invariants of `cqh` (Container Query Height) unit resolution: Non-Negativity and Linearity.

---

### 1. Architectural Overview
In the Blink rendering engine, the `cqh` unit represents $1\%$ of the query container's explicit content-box height. The resolution pipeline converts a parsed `CSSPrimitiveValue` into a physical or layout `LayoutUnit` (or `float`) during style recalculation via `CSSToLengthConversionData`.

Let $H_c$ be the resolved content-box height of the nearest ancestor query container with a valid `container-type` (`size` or `inline-size` where applicable to physical axes). The resolution function $R(v, H_c)$ for a given CSS numeric value $v$ (in `cqh`) is defined as:

$$R(v, H_c) = v \times \frac{H_c}{100}$$

---

### 2. Audit of Non-Negativity

The principle of non-negativity in `cqh` resolution must be evaluated across two distinct domains: **The Basis ($H_c$)** and **The Resolved Output ($R$)**.

#### A. Basis Non-Negativity (Strict Invariant)
The basis of the `cqh` unit—the container's height $H_c$—is strictly non-negative. 
* **Mechanism:** Within `LayoutBox` and `NGFragment`, content-box dimensions are derived by subtracting `border` and `padding` from the border-box size. Under the CSS Box Model specification enforced by Blink's LayoutNG, if `border + padding > border_box_height`, the content-box height is clamped to `0px`.
* **Assertion:** $\forall \text{ containers}, \; H_c \ge 0$. Consequently, the base unit $1\text{cqh} = \frac{H_c}{100}$ is strictly $\ge 0$. A container cannot possess a negative height, preventing sign-inversion anomalies during unit resolution.

#### B. Output Non-Negativity (Property-Dependent)
While the basis $1\text{cqh}$ is non-negative, the scalar multiplier $v$ provided by the author can be negative (e.g., `-5cqh`). 
* **Intermediate Resolution:** During `CSSLengthResolver::ZoomedComputedPixels()`, Blink permits negative outputs if $v < 0$. This is required to support properties where negative lengths are valid (e.g., `margin-top: -10cqh`, `top: -5cqh`, `transform: translateY(-50cqh)`).
* **Clamping Phase:** Non-negativity for restricted properties (e.g., `height`, `padding-top`, `border-width`) is **not** enforced by the `cqh` resolver itself. Instead, it is enforced downstream by `CSSPropertyParser` (at parse time for direct values) or by `Length::NonNegativeToCalculated()` / `ClampTo()` during `StyleBuilder` application when resolving `calc()` expressions containing `cqh`.

---

### 3. Audit of Linearity

Within the context of CSS length resolution, linearity dictates that the resolution function $R(v, H_c)$ must satisfy the properties of **homogeneity** (scaling) and **additivity** (superposition).

#### A. Homogeneity (Scalar Linearity)
For a fixed container height $H_c$, the resolved length scales linearly with the input value $v$, and vice versa:
$$R(\alpha \cdot v, H_c) = \alpha \cdot R(v, H_c)$$
$$R(v, \beta \cdot H_c) = \beta \cdot R(v, H_c)$$

* **Blink Implementation:** `CSSToLengthConversionData::ContainerSizes` fetches $H_c$ as a `double` or `LayoutUnit`, divides by $100.0$, and multiplies by the `double` representation of $v$ (along with the current `zoom` factor). This is a purely linear floating-point operation.

#### B. Additivity (Superposition in `calc()` and Interpolation)
For any two `cqh` values $v_1$ and $v_2$:
$$R(v_1 + v_2, H_c) = R(v_1, H_c) + R(v_2, H_c)$$

* **Blink Implementation:** When combined inside `CSSMathExpressionNode` (e.g., `calc(10cqh + 20cqh)` or CSS Transitions/Animations), `cqh` values are treated as a canonical linear vector space. Blink simplifies same-unit additions prior to basis multiplication or resolves them linearly within `CalculationValue` trees.

#### C. Deviations from Strict Linearity (Edge Cases)
Agent 395 identifies two architectural boundaries where strict mathematical linearity breaks down in Blink:

1. **Subpixel Quantization (`LayoutUnit` Clamping):**
   While intermediate CSS resolution occurs in `double` or `float` precision, final layout consumption often casts the result to `LayoutUnit` (a fixed-point representation with $\frac{1}{64}\text{px}$ precision). 
   * *Impact:* $R(v_1, H_c) + R(v_2, H_c)$ may differ from $R(v_1 + v_2, H_c)$ by up to $\frac{1}{64}\text{px}$ due to discrete truncation/rounding steps at the layout boundary.
2. **Fallback Resolution (Missing Container Context):**
   If an element uses `cqh` but has no eligible query container ancestor, the specification dictates that `cqh` resolves against the **Small Viewport Height (`svh`)**. While still linear with respect to `svh`, the resolution function experiences a piecewise discontinuity if DOM mutations dynamically insert or remove a `container-type` boundary.

---

### 4. Summary Conclusion
* **Non-Negativity:** **PASS.** The `1cqh` basis is strictly $\ge 0$ via LayoutNG box-sizing guarantees. Negative scalar multipliers are correctly preserved for signed properties and clamped at the `StyleBuilder` level for unsigned properties.
* **Linearity:** **PASS (within floating-point and fixed-point constraints).** Resolution is a direct linear mapping $f(v, H_c) = 0.01 \cdot v \cdot H_c \cdot \text{zoom}$, preserving vector-space operations for `calc()` and style interpolation, subject only to standard `LayoutUnit` $\frac{1}{64}\text{px}$ quantization.