**AUDIT REPORT: Blink MathML Fraction Bar Thickness**
**Agent:** 371
**Component:** `Blink>MathML` (LayoutNGMathML)
**Subject:** Strictly Positive Lower Bound for Fraction Bar Thickness (`linethickness`)

### 1. Executive Summary
In the Chromium Blink rendering engine, the thickness of the `<mfrac>` fraction bar is determined by the `linethickness` attribute or the OpenType `MATH` table defaults. However, unlike standard CSS borders in certain legacy engines—which may snap to `1px` to remain visible if specified as a sub-pixel value—**Blink MathML does not enforce a `1px` device-pixel floor.** 

Instead, the strictly positive lower bound is dictated exclusively by **Blink’s `LayoutUnit` sub-pixel precision limit** during layout, and **Skia’s floating-point anti-aliasing** during painting.

### 2. Specification Compliance (MathML Core)
Per the **MathML Core specification** (Section 3.3.2 `<mfrac>`):
* The `linethickness` attribute accepts a `<length-percentage>`.
* Default value is `medium` (resolved to the OpenType MATH parameter `FractionRuleThickness`).
* Negative values are clamped to `0` (or treated as invalid, falling back to default depending on parsing phase).
* **Crucial Audit Point:** The specification does *not* mandate a minimum visible thickness (e.g., `1px`) for strictly positive values ($0 < \text{thickness} < 1\text{px}$).

### 3. Blink Implementation Details

#### A. Layout Phase (`NGMathFractionLayoutAlgorithm`)
1. **Default Retrieval:** Blink queries the primary font's OpenType `MATH` table via HarfBuzz (`hb_ot_math_get_constant`) for `HB_OT_MATH_CONSTANT_FRACTION_RULE_THICKNESS`. If the font lacks a `MATH` table, a fallback based on the font's underline thickness or a fraction of `1em` is used.
2. **Attribute Resolution:** If `linethickness` is present, `LengthUtils` resolves the CSS length against the current style and font metrics into a `LayoutUnit`.
3. **Clamping:** The resolved thickness is clamped such that $\text{thickness} \ge 0$.

#### B. The Strictly Positive Lower Bound (`LayoutUnit`)
Blink uses fixed-point arithmetic (`LayoutUnit`) with **1/64th of a CSS pixel** precision to store layout geometry.
* **Mathematical Lower Bound:** The smallest strictly positive value representable in Blink's layout tree for the fraction bar thickness is **`LayoutUnit::FromRawValue(1)`**, which equals **$\frac{1}{64}\text{px}$ ($0.015625\text{ CSS pixels}$)**.
* **Underflow Behavior:** Any authored value strictly greater than $0$ but less than $\frac{1}{128}\text{px}$ (assuming standard rounding) or $\frac{1}{64}\text{px}$ (if floored) will underflow to `LayoutUnit(0)`. 
* Once quantized to `LayoutUnit(0)`, the fraction is treated as a stacked "atop" expression (like a binomial coefficient), and the bar is omitted entirely from both layout spacing and painting.

#### C. Paint Phase (`NGMathMLPainter`)
When `LineThickness > LayoutUnit(0)`:
1. `NGMathMLPainter::PaintFractionBar` constructs a `PhysicalRect` with a height equal to the quantized `LayoutUnit` thickness.
2. This rect is converted to a `gfx::RectF` (floating-point) and passed to `GraphicsContext::FillRect`.
3. **Sub-pixel Rendering:** Skia does not snap this rect to a minimum `1px` height. Instead, a fraction bar with a height of $\frac{1}{64}\text{px}$ is rendered using **alpha-blended anti-aliasing**. 
4. **Visual Lower Bound (8-bit Color):** In standard 8-bit-per-channel sRGB rendering, alpha values below $\frac{1}{255}$ ($\approx 0.0039$) become completely transparent. Since $\frac{1}{64} = 0.015625 > \frac{1}{255}$, a `LayoutUnit::FromRawValue(1)` bar on a 1x DPI display will still register a non-zero alpha value (approx. `alpha = 4` out of `255`), rendering as an almost imperceptible, faint line rather than disappearing completely.

### 4. Audit Summary Table

| Metric | Value | Mechanism |
| :--- | :--- | :--- |
| **Specification Floor** | $> 0\text{px}$ (No minimum floor) | W3C MathML Core |
| **Layout Engine Floor** | $0.015625\text{px}$ ($\frac{1}{64}\text{px}$) | `blink::LayoutUnit::Epsilon()` |
| **Paint Engine Floor** | $\approx 0.0039\text{px}$ ($\frac{1}{255}\text{px}$ at 1x DPI) | Skia 8-bit Alpha Quantization |
| **1px Snapping** | **Disabled** | Sub-pixel positioning / AA used |

**Conclusion:** For a fraction bar in Blink MathML to remain strictly positive in layout and trigger a paint operation, the computed `linethickness` must resolve to at least **`0.015625px`** ($\frac{1}{64}\text{px}$).