**AUDIT REPORT: BLINK TEXT STRIKETHROUGH METRICS**  
**AGENT ID:** 352  
**TARGET SUBSYSTEM:** `third_party/blink/renderer/platform/fonts/` & `core/paint/`  
**SUBJECT:** Strikethrough Offset and Thickness Calculation  

---

### 1. EXECUTIVE SUMMARY
In the Chromium/Blink rendering engine, the calculation of the text strikethrough (line-through) offset is governed by the `FontMetrics` class and applied during the paint phase by `TextDecorationOffset` and `AppliedDecorationPainter`. 

Blink prioritizes explicit typographical tables embedded within the font file (`OS/2`) via Skia. When font tables are missing, corrupt, or zeroed out, Blink falls back to heuristic calculations derived from the font's **x-height** or **ascent**.

---

### 2. DATA EXTRACTION PIPELINE (`SimpleFontData`)
During font initialization (`SimpleFontData::PlatformInit`), Blink queries the underlying Skia `SkFont` to populate `FontMetrics`. Skia extracts the `yStrikeoutPosition` and `yStrikeoutSize` directly from the TrueType/OpenType `OS/2` table.

#### A. Primary Path: Font Table Metrics
Blink requests `SkFontMetrics` via `SkFont::getMetrics(&metrics)`.
*   **Position:** Extracted from `metrics.fStrikeoutPosition`.
*   **Thickness:** Extracted from `metrics.fStrikeoutThickness`.

*Note on Coordinate Systems:* OpenType defines `yStrikeoutPosition` as a positive offset above the baseline. Skia negates this value so that offsets *above* the baseline are negative (matching Y-down screen coordinates). Blink subsequently negates or adjusts this value depending on whether it is storing the metric in `FontMetrics` (where up is often positive) or calculating final paint coordinates (where Y-down is positive).

#### B. Fallback Path: Heuristics
If the font lacks an `OS/2` table, or if Skia reports `hasStrikeoutPosition()` as false (or 0), Blink synthesizes the metrics using the following fallback hierarchy:

1.  **X-Height Heuristic (Preferred Fallback):**
    If the font has a valid, positive `x-height` (the height of the lowercase 'x'):
    $$\text{Strikethrough Offset} = \text{x-height} \times 0.5$$
    *(Places the line exactly halfway up the lowercase characters).*

2.  **Ascent Heuristic (Secondary Fallback):**
    If `x-height` is unavailable or $\le 0$, Blink falls back to the font's `ascent`:
    $$\text{Strikethrough Offset} = \text{Ascent} \times \frac{3}{8} \quad (\text{or } \approx 0.375 \times \text{Ascent})$$
    *(Note: In some legacy paths, if x-height itself is synthesized, x-height is calculated as $0.56 \times \text{Ascent}$, making the strikethrough effectively $0.28 \times \text{Ascent}$).*

3.  **Thickness Fallback:**
    If `fStrikeoutThickness` is missing, it defaults to the underline thickness, or heuristically:
    $$\text{Thickness} = \frac{\text{Font Size}}{13.0} \quad (\text{clamped to a minimum of } 1.0\text{px})$$

---

### 3. PAINT-TIME OFFSET CALCULATION
During the paint phase (handled by `TextDecorationInfo` and `NGTextPainter`), the abstract metric must be converted into a physical layout offset relative to the text box's baseline.

#### A. Horizontal Writing Mode
Given a baseline at $Y_{\text{baseline}}$, the exact $Y$ coordinate for the top of the strikethrough stroke is calculated as:

$$Y_{\text{paint}} = Y_{\text{baseline}} - \text{StrikeoutPosition}$$

#### B. Vertical Writing Mode (`vertical-rl`, `vertical-lr`)
When text is rendered vertically, the strikethrough behaviour depends on the `text-orientation` CSS property:
*   **`sideways`:** The metric is calculated identically to horizontal text, then rotated $90^\circ$ with the glyph run.
*   **`mixed` or `upright`:** The baseline is frequently central. Blink ignores the `OS/2` strikeout position (which is calibrated for Roman baselines) and forces the strikethrough to the exact geometric center of the em-box ($X_{\text{center}}$).

---

### 4. PIXEL SNAPPING & ANTI-ALIASING
To prevent blurry, half-pixel lines on standard DPI displays, Blink applies pixel-snapping before issuing the draw call to Skia (`cc::PaintCanvas`), though this behavior differs slightly between thickness and position:

1.  **Thickness Rounding:** 
    $$\text{Snapped Thickness} = \max\left(1.0, \text{round}(\text{Thickness})\right)$$
    *(Note: Under high-DPI/zoom or when `text-decoration-thickness` is explicitly set via CSS, fractional thicknesses may be preserved).*
2.  **Position Rounding:**
    The calculated offset is rounded to the nearest device pixel. To ensure the line grows *downward* (or sits evenly) without shifting the visual center, Blink calculates the center of the stroke, snaps it, and offsets by half the thickness:
    $$Y_{\text{final}} = \text{round}\left(Y_{\text{baseline}} - \text{StrikeoutPosition}\right)$$

---

### 5. CSS OVERRIDES (LEVEL 4 TEXT DECORATION)
As of recent Chromium milestones implementing **CSS Text Decoration Module Level 4**:
*   **Position:** Unlike underlines (which can be modified via `text-underline-offset`), CSS provides **no property** to manually offset a `line-through`. It is strictly bound to the font metrics audited above.
*   **Thickness:** The `OS/2` `yStrikeoutSize` **can** be overridden by the author using the `text-decoration-thickness` property (accepting `<length>`, `<percentage>`, or `from-font`). When overridden, Blink shifts the $Y_{\text{paint}}$ coordinate by $\frac{\Delta\text{Thickness}}{2}$ to keep the stroke centered on the original `StrikeoutPosition` axis.

---
**END OF REPORT**  
*Agent 352 signing off.*