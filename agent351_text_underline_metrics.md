**Agent 351 // Blink Layout & Paint Audit**
**Subject:** Text Underline Metrics, Positioning, and Thickness Bounds
**Component:** `third_party/blink/renderer/core/paint/text_decoration_info.cc` & `font_metrics.cc`

Here is the technical audit of how the Blink rendering engine calculates, bounds, and snaps text underline position and thickness.

---

### 1. Baseline Extraction (OpenType Metrics)
Blink initially queries the underlying `SimpleFontData` (via Skia/HarfBuzz) to extract raw metrics from the font's `post` (PostScript) table:
*   **Raw Position:** `underlinePosition` (typically negative in font design units, indicating distance below the baseline; Blink inverts this so positive values move downward toward the descent).
*   **Raw Thickness:** `underlineThickness`.

If the font lacks reliable metrics or reports `0`, Blink triggers internal heuristics based on the font's Ascent, Descent, and Em-height (`ComputedSize`).

---

### 2. Underline Thickness Bounds
Blink calculates thickness in `TextDecorationInfo::ComputeUnderlineThickness`. The engine must prevent hairline disappears at small font sizes and overly heavy bars in broken fonts.

*   **CSS Override (`text-decoration-thickness`):** 
    *   If `from-font` is specified, Blink uses the raw font metric.
    *   If a `<length>` or `<percentage>` is specified, it overrides the font metric (percentages are resolved against `1em`).
*   **Auto Heuristic (Fallback):** If `auto` is used and the font metric is invalid, thickness defaults to roughly `ComputedSize / 14.0f` (historically bounded between `1/14` and `1/18` of the em-box depending on platform).
*   **Lower Bound (Minimum Thickness):** 
    *   **Floor:** `1.0f` device pixel (or CSS pixel, depending on current zoom/DPR scaling phase). 
    *   Even if `text-decoration-thickness: 0.1px` is specified in CSS, Blink clamps the resolved thickness to a minimum of **1 device pixel** during paint to ensure visibility, unless explicitly set to `0px`.
*   **Pixel Snapping:** Thickness is typically rounded to the nearest integer device pixel (`floorf(thickness + 0.5f)`) to prevent anti-aliased blurring along the horizontal axis of the line.

---

### 3. Underline Position Bounds
Positioning is handled primarily in `TextDecorationInfo::ComputeUnderlineOffset`. Blink resolves the vertical offset relative to the **alphabetic baseline** (or ideological baseline in vertical writing modes).

#### A. `text-underline-position: auto` (Default)
*   **Metric Resolution:** Uses the font's `underlinePosition`. If missing, falls back to roughly `Ascent / 8.0f` or `MaxDescent / 2.0f` below the baseline.
*   **Upper Bound (Baseline Collision):** For `auto`, Blink ensures the underline does not cross above the alphabetic baseline unless explicitly forced by `text-underline-offset`. 
*   **Lower Bound (Descent Clipping - Historical vs. Modern):** 
    *   *Legacy behavior:* Clamped the underline so that `offset + thickness <= MaxDescent`.
    *   *Modern Chromium (post-CSS Text Decor 4):* Allows underlines to bleed slightly outside the font's descent box if modified by `text-underline-offset`, though the default `auto` computation still softly targets the space between the baseline and `MaxDescent`.
*   **Gap Enforcement:** Blink enforces a minimum **1px gap** between the alphabetic baseline and the top edge of the underline when resolving `auto` at small font sizes.

#### B. `text-underline-position: under`
Designed for CJK and mathematical typography to clear all descenders (g, j, p, q, y).
*   **Calculation:** Blink bypasses the font's `underlinePosition` table entirely.
*   **Position:** Placed at the bottom of the element's **em-box** or the font's **MaxDescent** (whichever is lower). 
*   **Stroke Adjustment:** When `under` is active, the resolved offset represents the *top* of the underline, ensuring the thickness grows *away* from the text descenders.

#### C. `text-underline-position: from-font`
*   Strictly trusts the OpenType `post` table metric without applying the standard `auto` heuristic adjustments, though device-pixel rounding still applies.

---

### 4. Painting & Snapping Adjustments (`BoxPainter` / `NGTextDecorationPainter`)
Before the metrics are handed off to Skia (`cc::PaintCanvas::drawLine` or `drawRect`), Blink performs final layout-space to device-space snapping:

1.  **Midpoint Calculation:** Skia strokes lines from the center of the path. Blink calculates the integer-snapped top edge of the underline (`round(baseline + offset)`), then shifts the coordinate down by `thickness / 2.0f` so the stroke aligns cleanly with the pixel grid.
2.  **Skip-Ink Bounds (`text-decoration-skip-ink: auto`):** Blink converts the underline into a `SkPath` clip region. It queries HarfBuzz for glyph outlines intersecting the vertical band `[underline_top -dilation, underline_bottom + dilation]`. The horizontal bounds of the underline are then segmented to clip out glyph descenders with an inline padding (dilation) roughly proportional to the underline thickness.

**Audit Status:** Nominal. Metrics conform to CSS Text Decoration Module Level 4 specifications.