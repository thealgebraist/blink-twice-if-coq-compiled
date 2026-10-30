**AUDIT LOG: BLINK LAYOUT ENGINE**
**AUDITOR:** Agent 350
**TARGET:** Text Emphasis Mark Positioning (`text-emphasis`)
**COMPONENT:** `third_party/blink/renderer/core/layout/inline/` & `platform/fonts/`

---

### 1. Executive Summary
In Chromium’s Blink engine, text emphasis mark positioning (used heavily in CJK typography via `-webkit-text-emphasis` / `text-emphasis`) is calculated during the inline layout phase and executed during the paint phase. The core offset calculation determines the distance from the **alphabetic or ideographic baseline** of the base text to the **baseline of the emphasis mark glyph**.

### 2. Primary Code Locations
*   `NGInlineLayoutAlgorithm` / `LogicalLineItems`: Resolves the line height expansion required to prevent emphasis marks from colliding with adjacent lines.
*   `ComputedStyle::GetTextEmphasisLineLogicalSide()`: Resolves `over`/`under` and `left`/`right` based on `writing-mode`.
*   `Font::EmphasisMarkAscent()` / `Font::EmphasisMarkDescent()` / `Font::EmphasisMarkHeight()`: Queries font metrics for the emphasis glyph.
*   `NGTextFragmentPainter` / `TextPainterBase`: Calculates the final physical offset `Y` (horizontal) or `X` (vertical) for Skia rendering.

---

### 3. Detailed Offset Calculation

The offset calculation is divided into two distinct phases: **Metric Extraction** and **Baseline Offset Resolution**.

#### Phase A: Metric Extraction
First, Blink determines the metrics of both the **Base Text Font** and the **Emphasis Mark Font**. 

1.  **Scale Factor:** By CSS specification, if the emphasis mark is rendered using a font glyph (rather than a synthesized shape), its size is scaled to **50% (`0.5f`)** of the base font size.
2.  **Glyph Metrics:** Blink resolves the `SimpleFontData` for the emphasis mark string. It extracts:
    *   `mark_ascent`: The ascent of the emphasis mark (at 0.5x scale).
    *   `mark_descent`: The descent of the emphasis mark (at 0.5x scale).
    *   `mark_height` = `mark_ascent + mark_descent`.

#### Phase B: Baseline-to-Baseline Offset Resolution
Blink calculates an `emphasis_mark_offset` (integer/LayoutUnit) relative to the base text’s primary baseline. The calculation diverges based on the resolved `LineLogicalSide` (`kOver` vs. `kUnder`).

Let:
*   $A_{base}$ = Base font Ascent (measured from baseline to top of em-box).
*   $D_{base}$ = Base font Descent (measured from baseline to bottom of em-box).
*   $A_{mark}$ = Emphasis mark Ascent.
*   $D_{mark}$ = Emphasis mark Descent.
*   $G$ = Gap (Ruby/Emphasis clearance gap, typically `0` or a fraction of the em-box depending on platform font metrics).

##### Case 1: Logical Side is `kOver` (Top in horizontal-tb, Right in vertical-rl)
The mark must sit *above* the base text's ascent. Because Skia draws text from the glyph's own baseline, Blink must push the mark up by the base ascent, plus the mark's own descent (so the bottom of the mark clears the top of the base character).

$$\text{Offset}_{\text{over}} = - (A_{base} + D_{mark} + G)$$

*(Note: Negative values move UP/LEFT in Blink's physical screen coordinates).*

##### Case 2: Logical Side is `kUnder` (Bottom in horizontal-tb, Left in vertical-rl)
The mark must sit *below* the base text's descent. Blink pushes the mark down by the base descent, plus the mark's own ascent (so the top of the mark clears the bottom of the base character).

$$\text{Offset}_{\text{under}} = D_{base} + A_{mark} + G$$

*(Note: Positive values move DOWN/RIGHT in Blink's physical screen coordinates).*

---

### 4. Vertical Writing Mode Adjustments (Central Baseline)
In vertical writing modes (`vertical-rl`, `vertical-lr`), CJK text uses a **central (ideographic) baseline** rather than an alphabetic baseline. 

When `FontBaseline` is `kCentralBaseline`:
*   The base text is centered around $0$.
*   $A_{base}$ becomes $\frac{\text{EmHeight}}{2}$.
*   $D_{base}$ becomes $\frac{\text{EmHeight}}{2}$.
*   The emphasis mark itself is also centered on its own central baseline, meaning $A_{mark}$ and $D_{mark}$ are effectively halved relative to the mark's bounding box, and the offset is applied along the **X-axis** instead of the Y-axis.

---

### 5. Ruby and Line-Height Interaction (Edge Cases)

During the `InlineLayoutAlgorithm` pass, Agent 350 notes the following layout constraints affecting the offset:

1.  **Annotation Overhang / Line Box Expansion:** 
    If the calculated $\text{Offset} + \text{MarkSize}$ exceeds the current `line-height` (specifies a taller ascent/descent than the `FontMetrics` provide), Blink registers an `AnnotationMetrics` expansion. This forces the `LogicalLineBox` to expand to prevent the emphasis mark from bleeding into the previous or next line.
2.  **Ruby Conflict Resolution:**
    If a character has *both* a `<rt>` (Ruby) annotation and a `text-emphasis` mark on the **same logical side**, the emphasis mark offset is calculated first (closest to the base text), and the Ruby offset is pushed outward by `mark_height`. (Note: CSS Text Decoration Level 3 specifies Ruby should be closer to base text, which is a known area of spec-compliance auditing in Blink's `NGAnnotationLayout`).

---
**END OF AUDIT REPORT**