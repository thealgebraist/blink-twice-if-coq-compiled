**AUDIT LOG: AGENT 482**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/html/forms/range_input_type.cc` & `step_range.cc`)
**SUBJECT:** `<input type="range">` Step Range Quantization Arithmetic

---

### 1. ARCHITECTURAL OVERVIEW
Blink does not perform range quantization using IEEE 754 floating-point numbers due to binary representation inaccuracies (e.g., `0.1 + 0.2 != 0.3`). Instead, Blink normalizes all values (`min`, `max`, `step`, `value`) into the **`blink::Decimal`** class (`platform/wtf/decimal.h`). 

`Decimal` represents numbers as:
$$\text{Value} = \text{Sign} \times \text{Coefficient} \times 10^{\text{Exponent}}$$
*   **Coefficient:** `uint64_t` (up to 18 digits of precision).
*   **Exponent:** `int32_t` ($-1023$ to $1023$).

### 2. Core Parameters (`StepRange`)
When auditing a range input, Blink establishes the following `Decimal` parameters:
*   **$V_{min}$ (Minimum):** Parsed from `min` attribute. Defaults to $0$.
*   **$V_{max}$ (Maximum):** Parsed from `max` attribute. Defaults to $100$. (If $V_{max} < V_{min}$, $V_{max}$ is clamped to $V_{min}$).
*   **$B$ (Step Base):** Defines the origin of the step grid. For `<input type="range">`, $B = V_{min}$. (Fallback is $0$ if $V_{min}$ is not defined, which is impossible for `range` as it defaults to $0$).
*   **$S$ (Step):** Parsed from `step` attribute. Defaults to $1$. If $S \le 0$ or `step="any"`, special handling applies (Note: `range` inputs do not support `any` in UI interactions; it falls back to default step $1$, though DOM validation behaves differently).

---

### 3. QUANTIZATION ARITHMETIC (`ClampValue`)

When a user interacts with the slider or sets `.value`, the raw input $V_{raw}$ is quantized into $V_{quant}$ through the following sequence in `StepRange::ClampValue`:

#### Phase A: Boundary Clamping (Pre-Step)
First, the raw value is constrained to the physical limits of the element:
$$V_{clamped} = \min(\max(V_{raw}, V_{min}), V_{max})$$

#### Phase B: Step Alignment (Rounding to Grid)
The engine calculates the offset from the Step Base ($B$) and divides by the Step ($S$) to find the step index ($N$). For `type="range"`, Blink uses **round-half-up** (towards $+\infty$) arithmetic.

1.  **Calculate Offset:** 
    $$\Delta = V_{clamped} - B$$
2.  **Calculate Step Index ($N$):**
    $$N = \text{round}\left(\frac{\Delta}{S}\right)$$
    *Internal `Decimal` implementation of `round`:*
    $$N = \left\lfloor \frac{\Delta}{S} + 0.5 \right\rfloor$$
3.  **Reconstruct Quantized Value:**
    $$V_{aligned} = B + (N \times S)$$

#### Phase C: Upper-Bound Correction (Step Mismatch)
If $(V_{max} - B) \pmod S \neq 0$, the round-half-up operation in Phase B might push $V_{aligned}$ past $V_{max}$. 

If $V_{aligned} > V_{max}$:
1.  Blink recalculates using a floor operation to find the highest valid step within bounds:
    $$N_{max} = \left\lfloor \frac{V_{max} - B}{S} \right\rfloor$$
2.  The corrected value becomes:
    $$V_{aligned} = B + (N_{max} \times S)$$

#### Phase D: Final Underflow Check
If $V_{aligned} < V_{min}$ (can occur if $B$ was somehow decoupled from $V_{min}$ in other input types, though rare in `range`):
$$V_{aligned} = B + \left(\left\lceil \frac{V_{min} - B}{S} \right\rceil \times S\right)$$

---

### 4. EDGE CASES & ANOMALIES IDENTIFIED

1.  **The "Unreachable Max" Phenomenon:**
    *   *Condition:* $V_{min} = 0$, $V_{max} = 10$, $S = 3$.
    *   *Arithmetic:* $N_{max} = \lfloor (10 - 0) / 3 \rfloor = 3$.
    *   *Result:* Maximum selectable value via quantization is $0 + (3 \times 3) = 9$. The value $10$ cannot be selected.
2.  **Step Scale Factor Overflow:**
    *   *Condition:* Extremely small steps ($S \to 10^{-20}$) with large ranges.
    *   *Arithmetic:* When $\frac{\Delta}{S}$ exceeds the `uint64_t` coefficient limit of `blink::Decimal` ($18$ significant digits), precision truncation occurs during division, causing erratic snapping near $V_{max}$.
3.  **Default Value Midpoint Calculation:**
    *   If `value` attribute is omitted, Blink calculates the default prior to quantization:
        $$V_{raw} = V_{min} + \frac{V_{max} - V_{min}}{2}$$
    *   This $V_{raw}$ is then immediately fed through Phases A–C. (e.g., $V_{min}=0, V_{max}=100, S=3 \implies V_{raw}=50 \implies N=\text{round}(16.666...) = 17 \implies V_{quant}=51$).

---
**STATUS:** Audit Complete. Arithmetic conforms to WHATWG HTML Living Standard (Section 4.10.5.1.12). Awaiting further instructions.