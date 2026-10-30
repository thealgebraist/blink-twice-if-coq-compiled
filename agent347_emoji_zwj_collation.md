**AUDIT LOG: BLINK ENGINE TEXT SHAPING & EMOJI COLLATION**  
**AGENT ID:** 347  
**SUBSYSTEM:** Blink (`third_party/blink/renderer/platform/fonts/`)  
**DEPENDENCIES:** HarfBuzz, ICU (International Components for Unicode), Skia  
**SUBJECT:** Zero-Width Joiner (ZWJ) Sequence Collation and Glyph Collapse Mechanics  

---

### 1. EXECUTIVE SUMMARY
This audit details the internal mechanics of "glyph sequence collapse" within the Chromium Blink rendering engine—the process by which a multi-codepoint Unicode Emoji ZWJ sequence is collated, segmented, and ultimately collapsed into a single Glyph ID (GID) for rasterization. It also identifies the failure modes (de-collation) where sequences fracture back into constituent glyphs.

---

### 2. THE COLLATION & SEGMENTATION PIPELINE

Before a ZWJ sequence can collapse into a single glyph, Blink must recognize the disparate codepoints as a single cohesive unit (Grapheme Cluster) and route them to the same font face.

#### 2.1. Grapheme Cluster Boundary Analysis
When a DOM string containing a ZWJ sequence (e.g., `U+1F468 U+200D U+1F469 U+200D U+1F467` — Family: Man, Woman, Girl) enters the layout pipeline:
1. **`HarfBuzzShaper`** invokes ICU’s `UBreakIterator` (specifically character/grapheme cluster boundaries, governed by UAX #29).
2. The presence of `U+200D` (ZWJ) between emoji-property characters inhibits the break iterator from splitting the run. The entire sequence is collated into a single non-breakable text run.

#### 2.2. Emoji Segmentation (`SymbolsIterator`)
Blink uses `SymbolsIterator` (leveraging `emojione` / ICU properties and Ragel-generated state machines in `emoji_segmentation_category.rl`) to tokenize text into emoji vs. text runs. 
* **Audit Note:** If the Ragel state machine does not recognize a newly minted Unicode ZWJ sequence grammar, the sequence is prematurely cleaved here, resulting in immediate sequence collapse failure before font shaping even occurs.

#### 2.3. Font Fallback and Run Collation (`FontFallbackIterator`)
Blink must find a single `SimpleFontData` instance capable of rendering the *entire* sequence.
* Blink queries the system’s color emoji font (e.g., *Noto Color Emoji*, *Apple Color Emoji*, *Segoe UI Emoji*).
* **Crucial Check:** Blink cannot verify if a font supports a *ligature* via standard `cmap` (Character to Glyph Index Mapping) lookups alone, because `cmap` only maps individual codepoints. Therefore, Blink verifies that all constituent base codepoints exist in the font, or passes the cluster to a known system emoji font, deferring the actual collapse validation to the HarfBuzz shaping phase.

---

### 3. GLYPH SEQUENCE COLLAPSE MECHANICS (HARFBUZZ)

The actual "collapse" of multiple Unicode codepoints into a single visual glyph occurs inside `HarfBuzzShaper::ShapeSegment`.

#### 3.1. Buffer Population
The UTF-16/UTF-8 string from Blink is loaded into an `hb_buffer_t`. At this stage, a 5-codepoint ZWJ sequence occupies 5 distinct positions in the buffer.
* `[U+1F468, U+200D, U+1F469, U+200D, U+1F467]`

#### 3.2. `cmap` Nominal Mapping
HarfBuzz maps each codepoint to its nominal Glyph ID (GID) using the font's `cmap` table. Variation Selectors (`U+FE0F`) are typically consumed here via `cmap` Format 14 (Unicode Variation Sequences) to select the emoji-style base GID over the text-style GID, or stripped if default.
* Buffer transforms to: `[GID_Man, GID_ZWJ, GID_Woman, GID_ZWJ, GID_Girl]`

#### 3.3. OpenType `GSUB` (Glyph Substitution) Ligation
HarfBuzz executes the OpenType layout engine against the font's `GSUB` table. Emoji ZWJ collapse relies almost exclusively on **Lookup Type 4 (Ligature Substitution)** or **Lookup Type 6 (Chained Contexts Substitution)** mapped to the `liga`, `clig`, or `ccmp` features.
1. The font's GSUB table contains a rule:  
   `if Sequence == (GID_Man + GID_ZWJ + GID_Woman + GID_ZWJ + GID_Girl) -> Substitute with GID_Family_MWG`.
2. **The Collapse:** HarfBuzz replaces the array of 5 GIDs in the `hb_buffer_t` with a **single GID** (`GID_Family_MWG`).
3. **Cluster Merging:** HarfBuzz updates the cluster array so that the single resulting GID maps back to the full byte-range of the original 5 codepoints in the DOM string (vital for cursor placement and selection in Blink).

#### 3.4. Color Table Resolution (Skia Handoff)
Once collapsed to a single GID, `ShapeResultBloberizer` extracts the GID and passes it to Skia. Skia renders the GID by looking it up in the font's color tables:
* **CBDT/CBLC** (PNG bitmaps - Android/Linux Noto)
* **sbix** (PNG bitmaps - macOS)
* **COLR/CPAL** (Vector layers - Windows/Modern Noto)

---

### 4. ANOMALIES: UNINTENDED SEQUENCE COLLAPSE (DE-COLLATION)

In auditing terminology, "collapse" can also refer to the **structural failure** of a ZWJ sequence, where it degrades (collapses) back into its raw, unjoined constituent glyphs (e.g., rendering 👨👩👧 instead of 👨‍👩‍👧). 

Agent 347 identifies four primary vectors in Blink where this failure occurs:

#### Vector A: `GSUB` Lookup Miss (Partial Collapse)
If a user receives an emoji from a newer Unicode version (e.g., Unicode 15.1 Phoenix `U+1F426 U+200D U+1F525`) on an OS with an outdated emoji font:
1. `cmap` succeeds (the font has both Bird `U+1F426` and Fire `U+1F525`).
2. `GSUB` fails (no ligature rule exists for this combination).
3. **Result:** HarfBuzz outputs `[GID_Bird, GID_ZWJ, GID_Fire]`. The `GID_ZWJ` has zero advance width and no contours. Blink renders Bird and Fire side-by-side. The sequence has collapsed into fallback constituents.

#### Vector B: Variation Selector (`U+FE0F`) Desynchronization
Many base characters in ZWJ sequences are text-default (e.g., Heart `U+2764` or Cloud `U+2601`) and require `U+FE0F` to trigger emoji presentation.
* **The Bug:** Some fonts include `U+FE0F` (mapped to a dummy GID) in their `GSUB` ligature chains, while others strip `U+FE0F` during `cmap` Format 14 processing. 
* If Blink's `FontFallbackIterator` or HarfBuzz retains the `FE0F` GID in the buffer when the font's `GSUB` table expects only `[Base + ZWJ + Base]`, the contiguous GID match fails, breaking the ligature.

#### Vector C: Buffer Cleaving via CSS Styling
If a web developer wraps part of a ZWJ sequence in a `<span>` with distinct layout-affecting CSS (e.g., `letter-spacing`, `font-family`, or `vertical-align`):
1. Blink's `NGInlineNode` splits the sequence into separate `ShapeResult` runs or isolated HarfBuzz sub-buffers.
2. Because `GSUB` ligation cannot cross `hb_buffer_t` boundaries, the sequence fails to collapse into a single glyph. (Note: Color changes alone are usually handled cleanly without breaking shaping, as color is a paint property, not a shaping property, though `COLR` palettes ignore CSS `color`).

#### Vector D: `CanvasRenderingContext2D` Text Metrics Discrepancy
When measuring text via `ctx.measureText()`, if the font fallback cascade differs slightly from the main DOM thread (e.g., due to asynchronous web font loading states), a ZWJ sequence may temporarily measure as the sum of $N$ constituent advance widths rather than $1$ collapsed GID advance width, causing layout thrashing (CLS) once the emoji font resolves and collapses the sequence.

---

### 5. AUDIT CONCLUSION
Blink’s ZWJ sequence collation is heavily reliant on synchronization between **Blink's `SymbolsIterator` (Ragel)**, **ICU's Grapheme Breaker**, and **HarfBuzz's `GSUB` execution**. 

To maintain zero-defect glyph collapse (ligation) and prevent fallback degradation (de-collation), Chromium must ensure that `emoji_segmentation_category.rl` is updated lockstep with ICU upgrades, and that `U+FE0F` normalization occurs *prior* to `FontFallbackIterator` commitment. 

**[END OF AUDIT LOG - AGENT 347]**