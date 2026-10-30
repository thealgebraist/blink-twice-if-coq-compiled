**AGENT 337 AUDIT REPORT: BLINK OPENTYPE GPOS VALUERECORD APPLICATION**
**COMPONENT:** `third_party/blink/renderer/platform/fonts/shaping/`
**SUBJECT:** HarfBuzz-to-Blink Coordinate Translation and Advance Modification

---

### 1. ARCHITECTURAL OVERVIEW
Blink does not parse raw OpenType `GPOS` (Glyph Positioning) tables directly during layout. Instead, it delegates table evaluation to **HarfBuzz** (`hb_shape`). HarfBuzz processes the `ValueRecord` structures (which contain `XPlacement`, `YPlacement`, `XAdvance`, `YAdvance`, and Device tables) and applies them to an internal buffer (`hb_buffer_t`).

Blink’s `HarfBuzzShaper` extracts the resolved values from `hb_glyph_position_t` and translates them into Blink's internal `ShapeResult` structures (`ShapeResult::RunInfo`).

### 2. COORDINATE SYSTEM & UNIT TRANSLATION
A critical audit point in Blink's text rendering is the conversion between HarfBuzz's mathematical coordinate space and Blink/Skia's screen coordinate space.

*   **Scale Factor:** HarfBuzz operates in `26.6` fixed-point format (1/64th of a pixel) by default in Blink. Blink converts these via `HarfBuzzUnitsToFloat()` (dividing by 64.0f) to `float` values, or directly into `LayoutUnit` depending on the pipeline stage.
*   **Axis Orientation (The Y-Axis Inversion):**
    *   **OpenType / HarfBuzz:** Uses a Cartesian coordinate system. `+X` moves right; **`+Y` moves UP**.
    *   **Blink / Skia:** Uses a screen coordinate system. `+X` moves right; **`+Y` moves DOWN**.

### 3. POSITION TRANSLATION (`XPlacement` / `YPlacement`)
In OpenType GPOS, `XPlacement` and `YPlacement` shift a glyph's rendering origin without affecting the pen position for subsequent glyphs.

In `hb_glyph_position_t`, these are represented as `x_offset` and `y_offset`.

#### Audit of Blink Application (`ShapeResult::InsertRun`):
When Blink reads the HarfBuzz buffer, it translates offsets into a `GlyphOffset` (a 2D vector):

1.  **Horizontal Text (LTR/RTL):**
    *   `XPlacement` (`pos.x_offset`) $\rightarrow$ `offset.x = HarfBuzzUnitsToFloat(pos.x_offset)`
    *   `YPlacement` (`pos.y_offset`) $\rightarrow$ `offset.y = -HarfBuzzUnitsToFloat(pos.y_offset)` *(Note the negation)*

2.  **Vertical Text:**
    *   In vertical writing modes, HarfBuzz shifts the baseline origin to the top-center of the glyph.
    *   Blink must invert **both** axes depending on how the vertical baseline is mapped to Skia's canvas, though standard `y_offset` negation remains the primary translation mechanism before rotation matrices are applied for upright vs. sideways orientation.

**Memory Optimization Audit:** Blink’s `GlyphData` array does not allocate memory for offsets unless a non-zero `x_offset` or `y_offset` is detected in the run. If a `ValueRecord` contains only Advance adjustments, the `offsets_` array in `RunInfo` remains null to save memory (`GlyphOffsetArray`).

### 4. ADVANCE ADDITION (`XAdvance` / `YAdvance`)
In OpenType GPOS, `XAdvance` and `YAdvance` modify how far the pen moves *after* the glyph is drawn (e.g., kerning).

#### HarfBuzz Pre-Calculation:
Before Blink sees the data, HarfBuzz takes the base advance from the `hmtx` (or `vmtx`) table and **adds** the GPOS `ValueRecord` advance:
$$\text{hb\_pos.x\_advance} = \text{hmtx.advanceWidth} + \text{GPOS.XAdvance}$$

#### Audit of Blink Application:
Blink consumes the *already-combined* advance from `hb_glyph_position_t` and accumulates it into the `RunInfo` and total `ShapeResult` width.

1.  **Horizontal Text (`!CanvasRotationInVertical`):**
    *   Blink reads `pos.x_advance`.
    *   `float advance = HarfBuzzUnitsToFloat(pos.x_advance);`
    *   **Post-GPOS Blink Additions:** Blink subsequently adds CSS-level adjustments (`letter-spacing`, `word-spacing`) directly to this `advance` variable *after* GPOS resolution.
    *   The final value is stored in `RunInfo::GlyphData::advance`.

2.  **Vertical Text:**
    *   HarfBuzz populates `pos.y_advance`. Because vertical text flows downward (negative Y in OpenType Cartesian space), HarfBuzz outputs a **negative** `y_advance`.
    *   Blink negates this value so that logical advances in `ShapeResult` remain positive numbers representing progression along the inline axis:
        `float advance = -HarfBuzzUnitsToFloat(pos.y_advance);`

### 5. RTL (RIGHT-TO-LEFT) Nuances
A frequent source of GPOS bugs is RTL text (e.g., Arabic cursive positioning).
*   HarfBuzz reverses the buffer for RTL shaping and applies GPOS `ValueRecords` in logical/visual order as dictated by the `GPOS` lookup flags.
*   When Blink iterates over the shaped `hb_buffer_t`, the glyphs are in **visual order** (left-to-right).
*   Both `x_advance` and `x_offset` remain standard (positive X is right) during Blink's ingestion; Blink does not need to negate `x_advance` for RTL because it processes the visual run from left to right when populating Skia's `SkTextBlobBuilder`.

### 6. SUMMARY MATRIX FOR BLINK GPOS INGESTION

| GPOS ValueRecord | HarfBuzz Output | Blink Transformation | Target Blink Structure |
| :--- | :--- | :--- | :--- |
| **XPlacement** | `pos.x_offset` | `+HarfBuzzUnitsToFloat(val)` | `RunInfo::GlyphOffsetArray.x` |
| **YPlacement** | `pos.y_offset` | `-HarfBuzzUnitsToFloat(val)` | `RunInfo::GlyphOffsetArray.y` |
| **XAdvance** (Horiz) | `pos.x_advance` | `+HarfBuzzUnitsToFloat(val)` | `RunInfo::GlyphData.advance` |
| **YAdvance** (Vert) | `pos.y_advance` | `-HarfBuzzUnitsToFloat(val)` | `RunInfo::GlyphData.advance` |

**Audit Conclusion:** Blink's `HarfBuzzShaper` correctly isolates GPOS placement from advance logic. The critical vulnerability surface lies in the **Y-axis inversion** for `YPlacement` and `YAdvance`, which is properly mitigated via unary negation during the `26.6` fixed-point to `float` conversion phase.

**// END REPORT - AGENT 337**