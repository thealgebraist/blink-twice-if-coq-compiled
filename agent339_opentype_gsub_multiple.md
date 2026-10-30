**AUDIT LOG: AGENT 339**
**TARGET:** Chromium Blink Text Rendering Engine (HarfBuzz Integration)
**COMPONENT:** OpenType `GSUB` LookupType 2 (Multiple Substitution)
**SUBJECT:** Glyph Sequence Expansion Mechanics & Vulnerability Surface

---

### 1. ARCHITECTURAL OVERVIEW
Blink does not parse OpenType tables directly; it delegates complex text shaping to **HarfBuzz** via `HarfBuzzShaper`. When auditing `GSUB` LookupType 2 (Multiple Substitution)—where a single glyph is replaced by a sequence of multiple glyphs ($1 \rightarrow N$ expansion)—the critical code paths reside in HarfBuzz’s `OT::MultipleSubstFormat1` and how Blink's `ShapeResult` consumes the expanded `hb_buffer_t`.

Typical use cases include decomposing ligatures into component glyphs or expanding a composite character into base + diacritics for finer positioning in subsequent `GPOS` passes.

---

### 2. GLYPH SEQUENCE EXPANSION MECHANICS

The expansion occurs during the `GSUB` substitution phase inside the HarfBuzz buffer (`hb_buffer_t`). The buffer manages two arrays during this phase: the `info` array (in-place input/output) and the `out_info` array (used when buffer expansion occurs).

#### Phase A: Table Parsing (`MultipleSubstFormat1::apply`)
1. **Coverage Check:** The current glyph ID at `buffer->idx` is checked against the `Coverage` table. If matched, it returns a `coverage_index`.
2. **Sequence Extraction:** The `coverage_index` indexes into the `Sequence` offset array. The corresponding `Sequence` table contains:
   * `glyphCount`: Number of replacement glyphs ($N$).
   * `substituteGlyphIDs[N]`: The array of new glyph IDs.

#### Phase B: Buffer Expansion (`hb_ot_apply_context_t::replace_glyphs`)
Depending on the value of `glyphCount` ($N$), the engine executes one of three paths:

1. **Deletion ($N = 0$):** 
   * Technically forbidden by earlier OpenType specs, but permitted in OpenType 1.8+. 
   * HarfBuzz handles this by calling `buffer->delete_glyph()`, advancing the input cursor without writing to the output buffer.
2. **1-to-1 Substitution ($N = 1$):** 
   * Handled in-place via `buffer->replace_glyph(glyph_id)`. No memory reallocation occurs.
3. **Expansion ($N > 1$):** 
   * **Buffer Allocation:** HarfBuzz calls `buffer->make_room_for(1, N)`. This checks if `buffer->len + (N - 1)` exceeds `buffer->allocated`. If so, `hb_buffer_t::enlarge()` reallocates the underlying arrays (typically doubling capacity).
   * **Glyph Injection:** The engine loops through `substituteGlyphIDs` and emits them via `buffer->output_glyph()`.

#### Phase C: Cluster & Property Propagation
When 1 glyph expands into $N$ glyphs, metadata must be synthesized for the $N-1$ new glyphs to maintain mapping back to the DOM text strings in Blink:

* **Cluster Values:** All $N$ output glyphs inherit the exact same `cluster` value (UTF-16/UTF-8 character index) as the original input glyph. This effectively turns the cluster into a multi-glyph cluster.
* **Glyph Properties (`GDEF`):** If the original glyph was a ligature or mark, HarfBuzz updates the `lig_props` field in `hb_glyph_info_t`. Each new glyph is assigned a distinct component index (`lig_comp = 1, 2, ... N`) so subsequent `GPOS` Mark-to-Ligature Or Mark-to-Base attachments know which sub-glyph to anchor to.

---

### 3. BLINK INTEGRATION (`HarfBuzzShaper` & `ShapeResult`)

Once `hb_shape()` completes, Blink extracts the expanded buffer:

1. **Run Construction:** `ShapeResult::InsertRun` iterates over `hb_buffer_get_glyph_infos` and `hb_buffer_get_glyph_positions`.
2. **Character-to-Glyph Mapping:** Because Multiple Substitution assigns the same `cluster` ID to all $N$ glyphs, Blink groups them into a single grapheme cluster representation within `HarfBuzzRunGlyphData`.
3. **Cursor & Selection Logic:** Because 1 character now maps to $N$ glyphs, Blink's `ShapeResult::CaretPositionForOffset` must divide the total advance width of the $N$ glyphs equally (or rely on `GDEF` ligature caret tables) if cursor placement is requested inside the expanded sequence.

---

### 4. AUDIT VECTORS & SECURITY CONTROLS

When auditing this mechanism for OOB (Out-of-Bounds) reads/writes, DoS (Denial of Service), or integer overflows, Agent 339 verifies the following controls:

#### Vector 1: The "Billion Laughs" Glyph Bomb (Exponential Expansion)
* **Scenario:** A malicious font chains multiple LookupType 2 tables together. Lookup 1 expands Glyph A into 10 Glyph Bs. Lookup 2 expands each Glyph B into 10 Glyph Cs, resulting in exponential memory exhaustion and CPU lockup.
* **Control Audited:** HarfBuzz implements strict expansion limits inside `hb_buffer_t`:
  * `HB_BUFFER_MAX_LEN_FACTOR` (Default: 64)
  * `HB_BUFFER_MAX_LEN_MIN` (Default: 16384)
  * `HB_BUFFER_MAX_OPS_FACTOR` (Default: 1024)
* **Mechanism:** `buffer->max_len` and `buffer->max_ops` are calculated at the start of shaping based on input string length. Every substitution decrements `max_ops`, and every `enlarge()` checks `max_len`. If exceeded, `buffer->shaping_failed` is set, and expansion halts gracefully.

#### Vector 2: Out-of-Bounds Read in `Sequence` Table
* **Scenario:** A malformed font specifies a `glyphCount` of `0xFFFF` at the very end of the `GSUB` table blob, attempting to force HarfBuzz to read past the mapped font memory.
* **Control Audited:** HarfBuzz's `Sanitizer` template (`hb_sanitize_context_t`).
* **Mechanism:** Before `apply()` is ever called, `Sequence::sanitize()` validates that `base_offset + sizeof(glyphCount) + (glyphCount * sizeof(HBGlyphID))` falls strictly within the `hb_blob_t` boundaries. Additionally, `Array16Of<HBGlyphID>` enforces compile-time and runtime bounds checking during the `apply()` loop.

#### Vector 3: Blink `HarfBuzzRunGlyphData` Overflow
* **Scenario:** Expansion succeeds in HarfBuzz, returning a massive glyph array that overflows Blink's internal run representation (`uint16_t` index limits).
* **Control Audited:** `ShapeResult::RunInfo` limits in Blink (`third_party/blink/renderer/platform/fonts/shaping/shape_result_inline_headers.h`).
* **Mechanism:** Blink caps the maximum number of glyphs per `RunInfo` (`kMaxGlyphs` = 32,768) to ensure glyph indices fit into 15-bit/16-bit structures. If a `GSUB` expansion causes a single cluster/run to exceed this limit, Blink splits the `RunInfo` into multiple contiguous sub-runs or truncates the visual output safely without heap corruption.

---

### 5. AUDIT CONCLUSION
**STATUS: SECURE.** 
The expansion mechanics in HarfBuzz utilize a double-buffered approach (`info` vs `out_info`) with strict arithmetic checks on `allocated` sizes. Exponential expansion attacks are neutralized by `HB_BUFFER_MAX_LEN` and `HB_BUFFER_MAX_OPS` governors. Blink safely ingests the expanded 1-to-Many cluster mappings by splitting oversized runs at the `ShapeResult` boundary. 

*End of Report. Agent 339 signing off.*