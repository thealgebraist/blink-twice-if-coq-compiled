**AUDIT REPORT: Blink Rendering Engine**  
**Subject:** Variable Font Optical Sizing (`opsz` Axis) Derivation  
**Agent:** 349  
**Status:** Complete  

---

### 1. Executive Summary
In the Blink rendering engine (Chromium), the derivation of the `opsz` (optical size) variation axis from the computed `font-size` is governed by the CSS Fonts Module Level 4 specification. When `font-optical-sizing` is set to `auto` (the default), Blink calculates the `opsz` value by converting the CSS pixel `font-size` into **typographic points (pt)**, completely independent of the page zoom level or device pixel ratio (DPR), before passing it to the HarfBuzz shaping engine and Skia typeface backends.

---

### 2. The Core Derivation Formula
According to the OpenType specification, the `opsz` axis expects a value representing the font size in typographic points. Blink derives this from the computed CSS `font-size` (which is internally resolved in CSS pixels).

Given the standard CSS unit relationship:
* $1\text{ inch} = 96\text{ CSS px}$
* $1\text{ inch} = 72\text{ pt}$

The conversion factor is $\frac{72}{96} = 0.75$ (or dividing by $\frac{4}{3}$).

$$\text{opsz} = \text{Computed Font Size (CSS px)} \times 0.75$$

**Example:**
If an element has `font-size: 16px`:
$$\text{opsz} = 16 \times 0.75 = 12.0$$

*Note on Implementation Nuance:* Historically, there were discrepancies across browser engines where Blink passed the raw CSS pixel value (`16`) directly to the `opsz` axis while WebKit/Gecko passed points (`12`). Blink has since aligned with the W3C CSSWG resolution (CSS Fonts 4) to normalize the value into points using the `0.75` multiplier, ensuring cross-browser rendering parity.

---

### 3. The Blink Pipeline & Resolution Order

The derivation and application of the `opsz` value occur across `StyleBuilder`, `FontBuilder`, and `FontDescription` within `third_party/blink/renderer/core/css/` and `platform/fonts/`.

#### Step A: Style Resolution
Blink checks the computed value of `font-optical-sizing`:
1. If `font-optical-sizing: none`, auto-derivation is aborted. The font renders at the typeface's default `opsz` instance (as defined in the font's `fvar` table).
2. If `font-optical-sizing: auto`, Blink flags the `FontDescription` object with `kAutoOpticalSizing`.

#### Step B: Size Extraction and Zoom Decoupling
Blink extracts the `ComputedSize` from `FontDescription`. 
* **Audit Finding (Zoom Isolation):** Blink uses the *unzoomed* computed CSS pixel size, **not** the `AdjustedSize` (which includes browser page zoom or `text-autosizer` multipliers). This is intentional. If a user zooms the page to 200%, a 12pt font should scale up geometrically like a magnifying glass; it should *not* morph into a 24pt display cut (which typically has thinner hairlines and tighter spacing, reducing readability for low-vision users).

#### Step C: Precedence and Overrides (The Cascade)
Before the derived `opsz` value is finalized in `FontCustomPlatformData`, Blink evaluates override conditions in the following strict order of precedence (lowest to highest):

1. **Font Default:** The default value in the OpenType `fvar` table.
2. **`@font-face` descriptor:** Any `font-variation-settings: 'opsz' X` defined in the `@font-face` rule.
3. **Auto-Derived `opsz`:** The calculated value ($\text{px} \times 0.75$) from `font-optical-sizing: auto`.
4. **Element `font-variation-settings`:** Explicit CSS declaration on the element (e.g., `font-variation-settings: 'opsz' 32`). If present, this completely overrides the `auto` calculation.

#### Step D: Font Table Clamping (Skia / HarfBuzz)
Once Blink calculates the float value for `opsz` and constructs the variation coordinates, the payload is sent to the underlying font shaping and rasterization engines (HarfBuzz and Skia/FreeType/CoreText/DirectWrite). 
* The engine reads the `fvar` (Font Variations) table of the loaded font binary.
* The derived `opsz` value is **clamped** to the `[minValue, maxValue]` range specified by the font designer in the `fvar` table. 
* *(e.g., If CSS `font-size` is `4px` $\rightarrow$ derived `opsz` is `3.0`. If the font's `opsz` axis range is `8.0` to `144.0`, the applied value is clamped to `8.0`).*

#### Step E: `avar` Table Mapping
Finally, if the font contains an `avar` (Axis Variations) table, the clamped `opsz` value undergoes piecewise linear interpolation to map the user-space `opsz` coordinate to the normalized $[-1, 1]$ design-space coordinate before glyph outlines (`glyf`/`CFF2`) and metrics (`HVAR`/`MVAR`) are interpolated.

---

### 4. Summary Checklist for Auditing
* **Source Value:** Computed `font-size` in CSS pixels.
* **Math:** $\text{CSS px} \times \frac{3}{4}$.
* **Affected by Browser Zoom?** No.
* **Affected by Device Pixel Ratio (Retina)?** No.
* **Affected by `font-size-adjust`?** Yes (if `font-size-adjust` alters the used font size, the `opsz` tracks the adjusted used size).
* **Overridden by `font-variation-settings`?** Yes, at the style level, not at the `@font-face` level.

**End of Report.**