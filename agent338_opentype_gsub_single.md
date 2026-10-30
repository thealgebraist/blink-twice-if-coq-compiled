**AGENT 338 - AUDIT REPORT**
**Target:** Chromium Blink Text Shaping Engine (`third_party/blink/renderer/platform/fonts/shaping/`)
**Dependency:** HarfBuzz (`third_party/harfbuzz-ng/src/OT/Layout/GSUB/`)
**Subject:** OpenType `GSUB` Lookup Type 1 (Single Substitution) Glyph ID Replacement Mapping

---

### 1. Executive Summary
Blink does not parse OpenType `GSUB` tables directly; it delegates OpenType layout operations to the integrated **HarfBuzz** shaping engine via `HarfBuzzShaper`. During the shaping phase, `GSUB` Lookup Type 1 (Single Substitution) replaces a single target Glyph ID (GID) in the `hb_buffer_t` with a single replacement GID. 

The mapping mechanism is strictly governed by the coverage table and one of two subtable formats defined in the OpenType specification (v1.9).

---

### 2. Prerequisite: Coverage Index Resolution
Before any GID replacement mapping occurs, the engine must validate if the input GID is eligible for substitution.
1. The shaper reads the `coverageOffset` from the `SingleSubst` subtable header.
2. The input GID is searched within the **Coverage Table** (Format 1: Individual glyph array, or Format 2: Contiguous glyph ranges).
3. **Audit Check:** 
   * If the GID is **not found**, the lookup aborts for this glyph (No-Op).
   * If **found**, the Coverage Table returns a zero-based `CoverageIndex`. This index drives the replacement mapping.

---

### 3. Glyph ID Replacement Mapping Formats

#### Format 1: Calculated Delta Mapping (`SingleSubstFormat1`)
Format 1 is used when the input GIDs and output GIDs have a uniform offset relationship (e.g., shifting `A-Z` to `a-z` where both sets are ordered identically in the font).

* **Structure:**
  * `substFormat` (uint16) = 1
  * `coverageOffset` (Offset16)
  * `deltaGlyphID` (int16) — *Signed 16-bit integer*
* **Mapping Algorithm:**
  $$\text{Output GID} = (\text{Input GID} + \text{deltaGlyphID}) \pmod{65536}$$
* **Audit Note (Modulo Arithmetic):** In HarfBuzz (`SingleSubstFormat1.hh`), the addition of the signed `deltaGlyphID` to the unsigned `hb_codepoint_t` (GID) is explicitly masked with `& 0xFFFF` to enforce modulo 65536 arithmetic. This prevents integer overflow/underflow vulnerabilities and satisfies the OpenType spec for wrapping around the 16-bit GID space. The `CoverageIndex` is only used as a boolean gate here, not for array indexing.

#### Format 2: Explicit Array Mapping (`SingleSubstFormat2`)
Format 2 is used when there is no mathematical relationship between the input GIDs and the replacement GIDs. It maps via a direct lookup array.

* **Structure:**
  * `substFormat` (uint16) = 2
  * `coverageOffset` (Offset16)
  * `glyphCount` (uint16)
  * `substituteGlyphIDs[glyphCount]` (uint16 array)
* **Mapping Algorithm:**
  $$\text{Output GID} = \text{substituteGlyphIDs}[\text{CoverageIndex}]$$
* **Audit Note (Bounds Checking):** A critical attack vector in font parsing is an out-of-bounds read where the `CoverageTable` yields a `CoverageIndex` $\ge$ `glyphCount`. HarfBuzz mitigates this in `SingleSubstFormat2::apply` by validating `CoverageIndex` against the sanitized length of the `substituteGlyphIDs` array (`substitute.len`). If out of bounds, the substitution silently fails and returns `false`.

---

### 4. Blink-to-HarfBuzz Execution Trace

1. **Buffer Initialization:** Blink's `HarfBuzzShaper::ShapeSegment` populates an `hb_buffer_t` with UTF-16/UTF-8 codepoints.
2. **Initial Mapping:** `hb_ot_shape` maps Unicode codepoints to initial GIDs via the font's `cmap` table.
3. **GSUB Execution:** HarfBuzz iterates through enabled features (e.g., `smcp`, `zero`, `salt`, `vert`) determined by Blink's `FontDescription` and CSS `font-feature-settings`.
4. **In-Place Replacement:** When Lookup Type 1 triggers, `c->replace_glyph(glyph_id)` is invoked on the `hb_ot_apply_context_t`. 
   * The `hb_glyph_info_t::codepoint` field (which holds the GID at this stage of the pipeline) is overwritten in-place.
   * Cluster values (`hb_glyph_info_t::cluster`) are preserved 1:1, maintaining Blink's ability to map shaped glyphs back to DOM text offsets for cursor placement and selection.
5. **Result Extraction:** `HarfBuzzShaper::ExtractShapeResults` reads the mutated GIDs from the `hb_buffer_t` and commits them to Blink's `ShapeResultRun` structures for Skia rendering.

---

### 5. Security & Sanitization Posture
* **Zero-Copy Sanitization:** HarfBuzz uses template-based memory overlays (`hb_sanitize_context_t`) to validate that `coverageOffset` and the `substituteGlyphIDs` array do not point outside the memory blob of the `GSUB` table before any shaping occurs.
* **Cycle Prevention:** Because Single Substitution (Type 1) does not recurse (unlike Chaining Contextual Substitutions, Types 5/6, or Extension Substitutions, Type 7), a single Type 1 subtable cannot cause an infinite loop on its own.

**Audit Status:** PASSED. Mapping logic conforms strictly to ISO/IEC 14496-22 (OpenType) with robust bounds and overflow protections. 
**Agent 338 signing off.**