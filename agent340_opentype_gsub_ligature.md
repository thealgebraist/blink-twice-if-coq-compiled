**AUDIT REPORT: BLINK OPENTYPE GSUB LIGATURE SUBSTITUTION**
**AUDITOR:** Agent 340
**TARGET:** Chromium Blink / HarfBuzz Shaping Engine (`hb-ot-layout-gsub-table.hh` / `LigatureSubstFormat1`)
**SUBJECT:** Sequence Prefix Reduction Mechanics and Vulnerability Surface

---

### 1. ARCHITECTURAL OVERVIEW
In the Blink rendering engine, OpenType Layout (OTL) tables—specifically the Glyph Substitution (`GSUB`) table—are processed via the integrated HarfBuzz shaping engine (`RunSegmenter` $\rightarrow$ `ShapeResult` $\rightarrow$ `HarfBuzzShaper`). 

During **Lookup Type 4 (Ligature Substitution)**, the engine replaces a sequence of multiple glyphs with a single ligature glyph. **Sequence Prefix Reduction** refers to the optimization and traversal mechanic where the initial glyph of a target sequence (the "prefix") is resolved via a `Coverage` table to prune the search space, reducing the matching operation strictly to the remaining suffix components.

---

### 2. SEQUENCE PREFIX REDUCTION MECHANICS

#### A. Binary Structure & Prefix Stripping
To optimize matching and reduce binary footprint, OpenType does not store the full glyph sequence in the `Ligature` subtable. If a target sequence is $[G_0, G_1, G_2, ..., G_{n-1}]$:
1. **Prefix Resolution:** The engine reads the current glyph at the buffer cursor ($G_0$) and queries the subtable's `Coverage` table.
2. **State Pruning:** If $G_0$ is not in the `Coverage` table, the sequence is immediately rejected ($O(\log N)$ or $O(1)$ depending on Coverage format).
3. **Index Mapping:** If $G_0$ is covered, the `Coverage` table returns an index into the `LigatureSet` array. Each `LigatureSet` corresponds *exclusively* to sequences beginning with $G_0$.
4. **Suffix Matching (The Reduction):** Because $G_0$ is implicitly validated by the `Coverage` lookup, the `Ligature` table itself omits $G_0$. The `componentCount` field states $n$, but the `componentGlyphIDs` array only stores $n - 1$ elements: $[G_1, G_2, ..., G_{n-1}]$.

#### B. Buffer Traversal & Skip Masking
When HarfBuzz executes `Ligature::apply()` (within `hb_ot_apply_context_t`):
* The engine instantiates a `skippy_iter_t` (skipping iterator) starting at `buffer->idx` (the prefix position).
* As it iterates through the `componentGlyphIDs` array ($0$ to `componentCount - 2`), the iterator advances through the `hb_buffer_t->info` array.
* **LookupFlags:** The prefix reduction must account for `LookupFlag` attributes (e.g., `IgnoreMarks`, `IgnoreBaseGlyphs`). Marks occurring between $G_0$ and $G_1$ are skipped during matching but preserved in the buffer.

#### C. Buffer Collapse (In-Place Reduction)
Once the suffix $[G_1 ... G_{n-1}]$ is matched at buffer indices $[idx_1 ... idx_{n-1}]$:
1. **Prefix Mutation:** The glyph at `buffer->idx` ($G_0$) is overwritten in-place with the `ligGlyph` ID.
2. **Cluster Merging:** If there are skipped glyphs (like combining marks) between matched components, their cluster values are merged with the prefix's cluster to preserve cursor positioning and text selection boundaries in Blink's `ShapeResult`.
3. **Component Deletion:** The matched suffix glyphs $[G_1 ... G_{n-1}]$ are removed, shifting any intervening skipped marks to sit immediately *after* the newly formed ligature glyph, and assigning them a `lig_comp` (ligature component) ID so downstream `GPOS` (Mark-to-Ligature) tables can attach them to the correct ligature component.

---

### 3. AUDIT FINDINGS: VULNERABILITY & EDGE-CASE VECTORS

As Agent 340, my audit of the prefix reduction logic highlights four critical areas where malformed font binaries can threaten Blink's stability or rendering performance:

#### Vector 1: Underflow on `componentCount`
* **Condition:** A malformed font specifies `componentCount = 0` or `componentCount = 1` in the `Ligature` table.
* **Impact:** Since the `componentGlyphIDs` array length is calculated as `componentCount - 1`, a value of `0` causes an unsigned integer underflow (`0 - 1 = 0xFFFF`), leading to an Out-Of-Bounds (OOB) read during sanitization or matching.
* **Mitigation Status:** HarfBuzz handles this via `UnsizedArrayOf` and explicit sanitization checks (`if (unlikely (!count)) return false;`), using `hb_Null` fallbacks if `count < 1`.

#### Vector 2: Algorithmic Complexity (DoS via Prefix Thrashing)
* **Condition:** A font defines a `Coverage` table matching a common glyph $G_0$, pointing to a massive `LigatureSet` containing thousands of `Ligature` tables with long `componentCount` arrays that almost match a crafted text payload, failing only on the final glyph $G_{n-1}$.
* **Impact:** Renders the prefix reduction optimization moot, forcing $O(M \times K)$ lookahead operations per character in Blink's shaping pass, hanging the renderer thread.
* **Mitigation Status:** Guarded by `HB_MAX_CONTEXT_LENGTH` (64) and `max_ops` budget counters inside `hb_ot_apply_context_t`. Once the operation budget is exhausted, shaping aborts cleanly.

#### Vector 3: Mark Reordering & Buffer Desynchronization
* **Condition:** During the collapse phase, if `IgnoreMarks` is set, the prefix $G_0$ absorbs the suffix components, and intervening marks are shifted.
* **Impact:** If the lookahead buffer size (`buffer->len`) is miscalculated relative to the `match_positions` array size, memmove operations shifting marks behind the reduced prefix can corrupt adjacent `hb_glyph_info_t` structs.
* **Mitigation Status:** HarfBuzz strictly caps `match_positions` to `HB_MAX_CONTEXT_LENGTH` and validates buffer space via `buffer->move_to()` and `merge_clusters()` before mutating the glyph stream.

#### Vector 4: Empty Prefix Coverage Cascading
* **Condition:** `ChainContextSubst` (Lookup Type 6) invokes a Ligature Substitution (Type 4) at a specific sequence index, where a previous operation deleted or mutated the expected prefix.
* **Impact:** State mismatch between the outer contextual lookup and the inner ligature prefix check.
* **Mitigation Status:** The inner `Coverage` check acts as a hard gate. Even if invoked via contextual chaining, if the current `buffer->cur()` does not match the Type 4 prefix `Coverage`, the lookup safely no-ops.

---

### 4. CONCLUSION
The Sequence Prefix Reduction mechanism within Blink's HarfBuzz integration is **SECURE**. Bounds checking via `hb_sanitize_context_t`, strict adherence to `HB_MAX_CONTEXT_LENGTH`, and operation budgeting effectively neutralize OOB reads and algorithmic complexity attacks stemming from malformed `componentCount` definitions. 

*End of Audit Report — Agent 340.*