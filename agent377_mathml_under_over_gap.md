**AUDIT REPORT: Blink MathML Under/Over Vertical Gap Clearance**
**Auditor:** Agent 377
**Component:** `Blink>MathML` (Layout & OpenType `MATH` Table Integration)
**Target:** `<munder>`, `<mover>`, `<munderover>` (`NGMathUnderOverLayoutAlgorithm`)

---

### 1. Executive Summary
In the Chromium Blink rendering engine (LayoutNG architecture), the vertical clearance (gap) between a base expression and its under- or over-script is governed by the W3C MathML Core specification. Blink resolves these clearances dynamically by querying metrics from the active font's OpenType `MATH` table, falling back to heuristic multiples of the font's metrics if a `MATH` table is absent.

 Vertical positioning is determined via a **two-constraint system**: a minimum gap clearance (`GapMin`) and a minimum baseline-to-baseline shift (`ShiftMin`/`BaselineDropMin`). The maximum of these two constraints dictates the final vertical offset.

---

### 2. Core Layout Algorithm
Vertical layout is handled in `third_party/blink/renderer/core/layout/mathml/math_under_over_layout_algorithm.cc`. The engine evaluates two distinct states for scripts: **Standard (Non-Accent)** and **Accent**.

#### A. Over-Script Clearance (`<mover>`, `<munderover>`)
The vertical position of an overscript relative to the base is determined by whether the `accent="true"` attribute is set.

**1. Non-Accent (`accent="false"` or default):**
*   **Minimum Clearance (Gap):** `OverbarVerticalGap` (standard bar) or `UpperLimitGapMin` (if base is a large operator with `movablelimits`).
    *   *Calculation:* The distance between the **ink ascent** of the base and the **ink descent** of the overscript must be $\ge \text{UpperLimitGapMin}$.
*   **Minimum Baseline Shift:** `UpperLimitBaselineRiseMin`
    *   *Calculation:* The distance between the **ink ascent** of the base and the **alphabetic baseline** of the overscript must be $\ge \text{UpperLimitBaselineRiseMin}$.
*   **Resolution:** 
    $$\text{Shift}_{\text{up}} = \max(\text{Base}_{\text{ascent}} + \text{UpperLimitGapMin} + \text{Over}_{\text{descent}}, \text{Base}_{\text{ascent}} + \text{UpperLimitBaselineRiseMin})$$

**2. Accent (`accent="true"`):**
*   **Minimum Clearance (Gap):** `AccentBaseHeight`
    *   *Calculation:* If the base's ink ascent is less than `AccentBaseHeight`, the accent is positioned as if the base had an ascent of `AccentBaseHeight`. Otherwise, the accent sits directly above the base's ink ascent.
*   **Vertical Gap:** `OverbarVerticalGap` (used in specific fallback paths) or `0` clearance above the `max(BaseAscent, AccentBaseHeight)` threshold, relying on the glyph's internal design bearings.

---

#### B. Under-Script Clearance (`<munder>`, `<munderover>`)
Under-scripts do not typically utilize the `accent` property in the same typographical manner, though MathML Core defines `accentunder`.

**1. Non-Accent (`accentunder="false"` or default):**
*   **Minimum Clearance (Gap):** `UnderbarVerticalGap` or `LowerLimitGapMin`.
    *   *Calculation:* The distance between the **ink descent** of the base and the **ink ascent** of the underscript must be $\ge \text{LowerLimitGapMin}$.
*   **Minimum Baseline Shift:** `LowerLimitBaselineDropMin`
    *   *Calculation:* The distance between the **ink descent** of the base and the **alphabetic baseline** of the underscript must be $\ge \text{LowerLimitBaselineDropMin}$.
*   **Resolution:**
    $$\text{Shift}_{\text{down}} = \max(\text{Base}_{\text{descent}} + \text{LowerLimitGapMin} + \text{Under}_{\text{ascent}}, \text{Base}_{\text{descent}} + \text{LowerLimitBaselineDropMin})$$

**2. Accent (`accentunder="true"`):**
*   **Minimum Clearance (Gap):** `0` (The underscript's ink ascent is aligned directly with the base's ink descent, without `LowerLimitBaselineDropMin` enforcement).

---

### 3. Stretchy Operator Exceptions
When the base or the script is a stretchy horizontal operator (e.g., `\underbrace`, `\overbrace`, `\overline`), Blink overrides standard `UpperLimit`/`LowerLimit` metrics with specific bar metrics from the `MATH` table:

*   **Overbar/Stretchy Over:**
    *   **Clearance:** `OverbarVerticalGap`
    *   **Extra Ascender:** `OverbarExtraAscender` (padding added above the overbar to prevent clipping with adjacent lines).
*   **Underbar/Stretchy Under:**
    *   **Clearance:** `UnderbarVerticalGap`
    *   **Extra Descender:** `UnderbarExtraDescender` (padding added below the underbar).

---

### 4. Bounding Box vs. Ink Box (Critical Audit Detail)
A frequent source of rendering regressions in Blink MathML involves the distinction between **Layout Box (Ascent/Descent)** and **Ink Box (Glyph Bounding Box)**:
*   **Spec Requirement:** OpenType `MATH` gap parameters (`UpperLimitGapMin`, `LowerLimitGapMin`) are designed to measure clearance from the **Ink Box** (actual glyph outline extremes) rather than the font's global typographical ascent/descent.
*   **Blink Implementation:** Blink computes the physical bounding box of the glyphs via HarfBuzz (`SimpleFontData::BoundsForGlyph`). If an element contains non-glyph layout boxes (like nested `<mrow>` or `<mfrac>`), Blink uses the union of their synthesized ink-overflow rectangles or layout box metrics to establish the baseline for the gap calculation.

---

### 5. Fallback Heuristics (No `MATH` Table)
If the active web font lacks an OpenType `MATH` table (e.g., Arial, Times New Roman), Blink's `MathMLStyle` / `OpenTypeMathSupport` synthesizes the clearance parameters using fallback constants based on `RuleThickness` (typically `0.05em` or derived from the underline thickness metric):

| Parameter | Fallback Approximation |
| :--- | :--- |
| `UpperLimitGapMin` | $\approx 3 \times \text{RuleThickness}$ |
| `UpperLimitBaselineRiseMin` | $0$ (relies purely on GapMin) |
| `LowerLimitGapMin` | $\approx 3 \times \text{RuleThickness}$ |
| `LowerLimitBaselineDropMin` | $0$ (relies purely on GapMin) |
| `OverbarVerticalGap` | $3 \times \text{RuleThickness}$ |
| `UnderbarVerticalGap` | $3 \times \text{RuleThickness}$ |
| `AccentBaseHeight` | Font `x-height` |

---

### 6. Known Audit Vectors / Edge Cases
1.  **Zero-Height Bases:** When a base is empty (e.g., `<mover><mi></mi><mo>^</mo></mover>`), `AccentBaseHeight` comparison can fail if ink bounds return `0`, causing accents to collapse onto the baseline.
2.  **Subpixel Rounding:** `LayoutUnit` (1/64th of a pixel) quantization of `UpperLimitGapMin` can cause 1px visual jumps between identical expressions at non-integer zoom levels.
3.  **Line-Box Pollution:** Non-math fonts used inside `<mtext>` within an `<mover>` force the container's ascent/descent to adopt the font's full line-height rather than tight glyph ink bounds, resulting in artificially large vertical gaps.

**End of Report.**