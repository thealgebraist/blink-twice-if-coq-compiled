**AUDIT LOG: AGENT 342**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/platform/fonts/shaping/`)
**SUBJECT:** Kerning Pair Advance Adjustment & Glyph Advance Addition

---

### 1. ARCHITECTURAL OVERVIEW
In the modern Blink text rendering pipeline (LayoutNG), Blink does not manually parse `kern` or `GPOS` tables to apply kerning pair adjustments in a vacuum. Instead, it delegates OpenType shaping to **HarfBuzz** via the `HarfBuzzShaper` class, while providing font metric callbacks through `HarfBuzzFace`. 

Kerning is applied as a modification to the **base horizontal advance** ($A_x$) and **glyph offset** ($O_x$) of a glyph within a `ShapeResult::RunInfo` structure during the shaping phase, prior to layout geometry calculation.

### 2. THE SHAPING PIPELINE & KERNING ENABLEMENT

#### A. Feature Resolution (`FontDescription` -> `hb_feature_t`)
Before shaping begins, Blink determines if kerning is active based on CSS properties (`font-kerning: auto | normal | none` and `font-feature-settings`).
*   **File:** `shaping/harfbuzz_shaper.cc`
*   **Mechanism:** `SetFontFeatures()` translates Blink's `FontDescription::GetKerning()` into the OpenType `kern` feature tag.
*   If enabled, `hb_feature_t` is initialized with `{HB_TAG('k','e','r','n'), 1, 0, (uint)-1}` and passed to `hb_shape()`.

#### B. Base Advance Retrieval
HarfBuzz queries Blink for the unadjusted, nominal glyph advances.
*   **File:** `shaping/harfbuzz_face.cc`
*   **Callback:** `HarfBuzzGetGlyphHorizontalAdvances()`
*   **Action:** Blink retrieves the raw advance widths from the underlying `SkTypeface` (Skia) and converts them into `hb_position_t` (16.16 fixed-point format or 26.6 depending on subpixel scaling configuration).

### 3. KERNING ADDITION TO GLYPH ADVANCE (CORE MECHANISM)

Inside the `hb_shape()` execution, HarfBuzz applies either the legacy TrueType `kern` table or the OpenType `GPOS` (Pair Positioning ` PairPosFormat1`/`2`) table. 

When a kerning pair (Glyph $i$, Glyph $i+1$) is matched, the adjustment value ($K$) is added directly to the `x_advance` of Glyph $i$ (for standard horizontal LTR/RTL text) in the `hb_glyph_position_t` buffer:

$$\text{hb\_glyph\_position\_t}[i].\text{x\_advance} \mathrel{+}= K$$

*(Note: Complex GPOS kerning may also modify `x_offset` and `y_offset`, which Blink captures separately).*

### 4. EXTRACTION & CONVERSION IN BLINK

Once `hb_shape()` completes, Blink extracts the kerning-adjusted advances from the HarfBuzz buffer and commits them to its internal `ShapeResult` representation.

*   **File:** `shaping/harfbuzz_shaper.cc` -> `ShapeResult::InsertRun()`
*   **File:** `shaping/shape_result.cc`

#### Step-by-Step Addition to Blink's GlyphData:
1.  **Buffer Iteration:** Blink iterates over `hb_glyph_info_t` and `hb_glyph_position_t`.
2.  **Fixed-Point Conversion:** The kerning-adjusted `hb_position_t` (`x_advance`) is converted back to Blink's internal `HarfBuzzPositionToFloat` (or `LayoutUnit` / `TextRunLayoutUnit`).
3.  **Subpixel Rounding (If Applicable):** 
    If `FontDescription::SubpixelPositioning()` is false (e.g., on certain low-DPI Windows/Linux configurations), the combined `[Base Advance + Kerning]` value is rounded to the nearest integer *after* kerning is applied, preventing cumulative rounding errors.
4.  **Storage in `HarfBuzzRunGlyphData`:**
    ```cpp
    // Conceptual representation in ShapeResult::RunInfo
    HarfBuzzRunGlyphData& glyph_data = run->glyph_data_[i];
    
    // 'advance' already contains (Nominal_Advance + Kerning_Adjustment)
    float advance = HarfBuzzPositionToFloat(glyph_position->x_advance); 
    
    // Further Blink-level adjustments (e.g., letter-spacing, word-spacing) 
    // are added ON TOP of the kerned advance at this stage.
    if (UNLIKELY(has_letter_spacing))
        advance += font_description.LetterSpacing();

    glyph_data.advance = advance;
    ```
5.  **Run Width Accumulation:** The `RunInfo::width_` is incremented by this final `advance` value:
    $$\text{RunWidth} = \sum_{i=0}^{n-1} (\text{BaseAdvance}_i + \text{Kerning}_i + \text{Tracking}_i)$$

### 5. AUDIT FINDINGS & EDGE CASES

*   **Precision Limit:** In `HarfBuzzRunGlyphData`, advances are stored as `float` (or `InlineLayoutUnit` during NG fragmentation). High-precision GPOS kerning adjustments survive all the way to the Skia `SkCanvas::drawGlyphs` call, which takes `SkPoint` positions calculated by cumulatively summing these advances in `ShapeResultBloberizer`.
*   **Run Boundaries:** **CRITICAL.** Kerning pairs *cannot* cross `RunInfo` boundaries. If a DOM node splits a kerning pair (e.g., `<span>V</span><span>A</span>`), Blink attempts to shape them together in `NGInlineNode::ShapeText` using a combined text buffer. However, if the font fallback, script, or style (other than color/decoration) changes between `V` and `A`, the shaper breaks the run, and the kerning adjustment $K$ is dropped (evaluates to `0`).
*   **Vertical Text:** For vertical writing modes (`writing-mode: vertical-rl`), the exact same pipeline applies, except HarfBuzz modifies `y_advance` via the `vkrn` feature tag, and Blink extracts `glyph_position->y_advance`.

**STATUS:** Pipeline verified. Kerning addition is tightly coupled to the HarfBuzz buffer extraction phase prior to `letter-spacing` injection. **AUDIT COMPLETE.**