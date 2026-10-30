**AUDIT REPORT: Blink MathML Fraction Vertical Gap Enforcement**
**Auditor:** Agent 372
**Target Subsystem:** Blink Rendering Engine (`third_party/blink/renderer/core/layout/mathml/`)
**Component:** `NGMathFractionLayoutAlgorithm`
**Reference Specification:** W3C MathML Core Specification (Section 3.3.2: `<mfrac>`)

---

### 1. Executive Summary
This audit details the vertical gap enforcement mechanisms for `<mfrac>` elements within the Chromium Blink layout engine. Vertical gap clearance is strictly governed by OpenType `MATH` table parameters, falling back to hardcoded heuristics only when font metrics are absent. The layout algorithm differentiates between two primary states: **Barred Fractions** (`linethickness > 0`) and **Atop/Stack Fractions** (`linethickness == 0`), crossed with two display states: **`displaystyle="true"`** and **`displaystyle="false"`** (inline).

---

### 2. Parameter Extraction (`OpenTypeMathSupport`)
Blink extracts vertical clearance constants from the active font’s OpenType `MATH` table via `MathConstants`. If the `MATH` table is missing, Blink falls back to empirical multiples of the font's `x-height` or `em` size.

#### A. Barred Fraction Parameters
*   `FractionNumeratorDisplayStyleShiftUp` / `FractionNumeratorShiftUp`
*   `FractionNumeratorDisplayStyleGapMin` / `FractionNumeratorGapMin`
*   `FractionRuleThickness` (Default thickness of the fraction bar)
*   `FractionDenominatorDisplayStyleShiftDown` / `FractionDenominatorShiftDown`
*   `FractionDenominatorDisplayStyleGapMin` / `FractionDenominatorGapMin`
*   `AxisHeight` (Vertical offset of the math axis from the baseline)

#### B. Atop (Zero-Bar) Parameters
*   `StackTopDisplayStyleShiftUp` / `StackTopShiftUp`
*   `StackDisplayStyleGapMin` / `StackGapMin`
*   `StackBottomDisplayStyleShiftDown` / `StackBottomShiftDown`

---

### 3. Enforcement Logic: Barred Fractions ($t > 0$)
When the computed `linethickness` ($t$) is greater than zero, the fraction bar is centered on the **Math Axis** ($A_h$). The bar extends vertically from $A_h - \frac{t}{2}$ to $A_h + \frac{t}{2}$.

#### Step 1: Initial Shift Determination
Blink queries the initial baseline shifts for the numerator ($S_{num}$) and denominator ($S_{den}$) based on the `MathStyle`:
*   **Display Style:** Uses `FractionNumeratorDisplayStyleShiftUp` and `FractionDenominatorDisplayStyleShiftDown`.
*   **Inline Style:** Uses `FractionNumeratorShiftUp` and `FractionDenominatorShiftDown`.

#### Step 2: Actual Clearance Calculation
Blink calculates the current physical gap between the ink bounding boxes (ascent/descent) of the children and the edges of the fraction bar:
*   $\text{ActualGap}_{num} = (S_{num} - D_{num}) - (A_h + \frac{t}{2})$
*   $\text{ActualGap}_{den} = (S_{den} - A_{den}) + (A_h - \frac{t}{2})$
*(Where $D_{num}$ is the numerator's descent and $A_{den}$ is the denominator's ascent).*

#### Step 3: Minimum Gap Enforcement (Clamping)
Blink retrieves `GapMin` ($G_{min}^{num}$ and $G_{min}^{den}$) based on `displaystyle`. If the actual gap is less than the minimum required gap, the shift is forcefully increased:

$$\text{Final } S_{num} = \max\left(S_{num}, \quad A_h + \frac{t}{2} + G_{min}^{num} + D_{num}\right)$$

$$\text{Final } S_{den} = \max\left(S_{den}, \quad -A_h + \frac{t}{2} + G_{min}^{den} + A_{den}\right)$$

---

### 4. Enforcement Logic: Atop / Stack Fractions ($t = 0$)
When `linethickness` is explicitly set to `0` (e.g., binomial coefficients), no bar is drawn, and the clearance is enforced directly between the numerator's descent and the denominator's ascent.

#### Step 1: Initial Shift Determination
*   $S_{num}$ = `StackTop[DisplayStyle]ShiftUp`
*   $S_{den}$ = `StackBottom[DisplayStyle]ShiftDown`

#### Step 2: Actual Gap Calculation
The total vertical distance between the bottom of the numerator and the top of the denominator is calculated as:
$$\text{ActualGap} = (S_{num} - D_{num}) + (S_{den} - A_{den})$$

#### Step 3: Deficit Resolution
Blink compares $\text{ActualGap}$ against $G_{min}$ (`Stack[DisplayStyle]GapMin`). If $\text{ActualGap} < G_{min}$, a deficit ($\Delta$) exists:
$$\Delta = G_{min} - \text{ActualGap}$$

Blink resolves this deficit by distributing it **equally** between the numerator and denominator shifts:
$$\text{Final } S_{num} = S_{num} + \frac{\Delta}{2}$$
$$\text{Final } S_{den} = S_{den} + \frac{\Delta}{2}$$

---

### 5. Box Model & Baseline Alignment
Once $\text{Final } S_{num}$ and $\text{Final } S_{den}$ are locked, `NGMathFractionLayoutAlgorithm` constructs the final fragment geometry:

1.  **Fraction Ascent:** $\max(A_{num} + \text{Final } S_{num}, \quad A_h + \frac{t}{2})$
2.  **Fraction Descent:** $\max(D_{den} + \text{Final } S_{den}, \quad -A_h + \frac{t}{2})$
3.  **Total Block Size:** $\text{Fraction Ascent} + \text{Fraction Descent} + \text{Borders/Padding}$

### 6. Audit Conclusion & Edge Cases
*   **Sub-pixel Rendering:** Blink does not pixel-snap `GapMin` during layout calculation, preserving layout fidelity under zoom, though paint-time snapping is applied to the fraction bar itself to prevent blurry rules.
*   **Negative `linethickness`:** Handled at the style/parsing level; clamped to `0` before reaching the layout algorithm.
*   **Compliance Status:** **PASS**. Blink's `NGMathFractionLayoutAlgorithm` strictly adheres to the W3C MathML Core specification and OpenType `MATH` layout mechanics.

**End of Report.**
*Agent 372 signing off.*