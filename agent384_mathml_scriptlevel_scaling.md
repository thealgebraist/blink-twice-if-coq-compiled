**AUDIT REPORT: Blink MathML `scriptlevel` Font Scaling**
**Auditor:** Agent 384
**Target Component:** Blink Rendering Engine (Chromium) — MathML Core Layout & Style Resolution (`ComputedStyle`, `StyleAdjuster`, `FontBuilder`)
**Specification Reference:** W3C MathML Core Specification (Section: *The `math-depth` property and `scriptlevel` attribute*)

---

### 1. Executive Summary
This audit details the internal mechanics of font size attenuation driven by the MathML `scriptlevel` attribute (mapped to the CSS `math-depth` property) within the Blink rendering engine. It also establishes the mathematical and programmatic positive bounds enforced to prevent zero-size collapse, sub-pixel vanishing, and floating-point overflow during deep or adversarial DOM nesting.

---

### 2. Size Attenuation Mechanics

In Blink’s implementation of MathML Core, `scriptlevel` does not directly manipulate font size in the parser. Instead, it maps to the internal CSS property `math-depth`, which subsequently dictates font scaling during the style calculation phase (`StyleResolver` / `FontBuilder`).

#### 2.1. The Base Multiplier (`scriptPercentScaleDown`)
Attenuation is primarily governed by the OpenType `MATH` table found in the active font face. 
* **Primary Factor ($S_1$):** `ScriptPercentScaleDown` (typically $0.71$ or $71\%$).
* **Secondary Factor ($S_2$):** `ScriptScriptPercentScaleDown` (typically $0.50$ or $50\%$).
* **Fallback Factor:** If the active font lacks an OpenType `MATH` table, Blink defaults to the MathML Core specification fallback:
  $$S_{\text{fallback}} = 0.71$$

#### 2.2. Attenuation Transitions (Delta Depth)
Let $D_{\text{parent}}$ be the inherited `math-depth` and $D_{\text{current}}$ be the computed `math-depth` of the current MathML node. The Font Builder computes the scale factor $M$ applied to the inherited `font-size` ($F_{\text{parent}}$) based on the transition from $D_{\text{parent}}$ to $D_{\text{current}}$:

1. **Transition $0 \to 1$:** 
   $$F_{\text{current}} = F_{\text{parent}} \times S_1$$
2. **Transition $0 \to 2$:** 
   $$F_{\text{current}} = F_{\text{parent}} \times S_2$$
3. **Transition $1 \to 2$:** 
   $$F_{\text{current}} = F_{\text{parent}} \times \left(\frac{S_2}{S_1}\right)$$
4. **General Arbitrary Transitions ($D_{\text{current}} > 2$ or $D < 0$):**
   For any depth change outside the explicit $[0, 2]$ OpenType optimization zone, Blink applies exponential attenuation using the base fallback ratio:
   $$F_{\text{current}} = F_{\text{parent}} \times (0.71)^{(D_{\text{current}} - D_{\text{parent}})}$$

*Note: If a node explicitly specifies a CSS `font-size` (or the legacy `mathsize` attribute), the `math-depth` scaling multiplier is bypassed for that specific node's local style resolution, though its `math-depth` value continues to propagate to descendants.*

---

### 3. Positive Bounds and Clamping

To maintain layout stability, prevent denial-of-service (DoS) via NaN/Infinity propagation, and ensure glyph legibility, Blink enforces strict positive bounds at three distinct layers: **State Representation**, **Lower-Bound Clamping (Attenuation Floor)**, and **Upper-Bound Clamping (Anti-Overflow)**.

#### 3.1. State Representation Bounds (`math-depth`)
The `scriptlevel` attribute accepts `<integer>`, `+<integer>`, or `-<integer>`. 
* Within Blink's `ComputedStyle`, `math-depth` is stored as a signed 16-bit integer (`int16_t`).
* **Bounds:** $[-32768, 32767]$. 
* **Audit Note:** Any parsed HTML attribute value exceeding these limits is clamped via `std::clamp` during CSS value conversion before reaching the font scaling algorithm.

#### 3.2. Lower Positive Bound (The Attenuation Floor)
Repeated nesting of `<msup>`, `<msub>`, or `<mfrac>` increments `math-depth`, driving $(0.71)^{\Delta D} \to 0$. Blink prevents font size collapse via two mechanisms:

1. **The OpenType `scriptMinSize` (Spec Constraint Check):**
   While legacy MathML3 utilized a strict `scriptminsize` (defaulting to `8pt`), **MathML Core deprecates and removes `scriptminsize` clamping** from the CSS `math-depth` calculation to ensure predictable CSS cascade behavior. Blink adheres to MathML Core: `math-depth` scaling itself does *not* halt at `8pt`.
2. **Engine Hard Floor:**
   * **Accessibility/User Preference Bound:** Blink applies `Settings::GetMinimumFontSize()` via `FontBuilder::CheckForMinimumFontSize()`. However, for mathematical layout integrity, MathML elements typically bypass standard text-zoom minimum font sizes unless configured via strict accessibility overrides.
   * **Float/Layout Zero-Guard:** In `FontDescription`, computed pixel values cannot be negative. If $D \to 32767$, floating-point underflow occurs. Blink clamps the final computed `font-size` to a non-negative `float` ($F \ge 0.0\text{px}$). When $F \to 0$, Skia/HarfBuzz ceases glyph rasterization safely without dividing by zero during metric scaling.

#### 3.3. Upper Positive Bound (Negative `scriptlevel` Anti-Overflow)
If an author specifies negative `scriptlevel` values (e.g., `<mstyle scriptlevel="-50">`), the attenuation formula inverts into an amplification formula:
$$M = (0.71)^{-\Delta D} \approx (1.40845)^{\Delta D}$$
Unchecked, this causes rapid floating-point overflow (`FLT_MAX`) and catastrophic memory allocation in the glyph cache.

Blink enforces the following upper positive bounds:
1. **Blink Max Font Size (`kMaximumAllowedFontSize`):**
   In `third_party/blink/renderer/platform/fonts/font_description.h` (and enforced during `StyleBuilder` application), Blink clamps all computed font sizes to a hard engine maximum—historically **`10000.0f` pixels** (or `LayoutUnit::Max()` divided by subpixel resolution in layout contexts).
2. **`LayoutUnit` Saturation:**
   When font metrics are converted to physical layout geometries (`LayoutNG`), dimensions are ingested into `LayoutUnit` (a 32-bit fixed-point value with 6 fractional bits).
   * **Max Positive Bound:** $\frac{2^{31} - 1}{64} \approx 33,554,431.98\text{px}$.
   * Saturated arithmetic (`ClampTo<LayoutUnit>`) guarantees that extreme negative `scriptlevel` values saturate at `LayoutUnit::Max()` rather than wrapping around to negative coordinates.

---

### 4. Audit Summary Table

| Parameter / Vector | Blink Internal Value / Mechanism | Security / Layout Impact |
| :--- | :--- | :--- |
| **Base Attenuation ($S_1$)** | OpenType `ScriptPercentScaleDown` (Fallback: `0.71f`) | Standardizes first-level sub/superscript sizing. |
| **Deep Attenuation ($S_2$)** | OpenType `ScriptScriptPercentScaleDown` (Fallback: `0.5041f`) | Standardizes second-level sizing ($0.71^2$). |
| **`math-depth` Storage** | `int16_t` ($-32768$ to $32767$) | Prevents integer overflow during relative (`+`/`-`) parsing. |
| **Min Positive Bound** | $0.0\text{f}$ (Sub-pixel underflow) | `scriptminsize` is omitted per MathML Core. Underflow safely skips Skia rasterization. |
| **Max Positive Bound** | Clamped at `kMaximumAllowedFontSize` / `LayoutUnit::Max()` | Mitigates DoS and Skia glyph cache OOM via negative `scriptlevel` amplification. |

**Status:** COMPLIANT. Blink's `math-depth` scaling accurately reflects the W3C MathML Core specification, delegating scaling factors to OpenType `MATH` tables where present and relying on standard Blink `FontBuilder` and `LayoutUnit` clamping to guarantee positive bound safety. 

*End of Report — Agent 384.*