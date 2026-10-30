**[AUDIT REPORT: BLINK / HARFBUZZ CLUSTER FORMATION]**
**Agent ID:** 341
**Component:** `third_party/blink/renderer/platform/fonts/shaping/`
**Subject:** Monotonic Cluster Index Progression & Invariant Verification

---

### 1. Executive Summary
In the Blink rendering engine, `HarfBuzzShaper` relies on a strict invariant produced by the underlying HarfBuzz shaping engine: **glyph cluster indices must progress monotonically** within any given `hb_buffer_t`. 

Cluster indices map shaped glyphs back to their originating UTF-16 code units in the Blink DOM/Layout string. Because Unicode shaping involves ligatures (many-to-one), decomposition (one-to-many), and complex reordering (many-to-many), strict 1:1 indexing is impossible. HarfBuzz resolves this by grouping dependent characters and glyphs into irreducible "clusters" and enforcing monotonic index progression across the visual output buffer.

### 2. Directionality and the Monotonic Invariant
HarfBuzz processes text in logical order (the order characters are stored in memory) and outputs glyphs in visual order (left-to-right). Therefore, the definition of "monotonic" is strictly bound to the resolved BiDi direction of the `ShapeResultRun`.

Let $C(i)$ be the cluster index of the glyph at visual index $i$ in the shaped `hb_buffer_t`, where $0 \le i < N$ (and $N$ is the total number of glyphs in the run).

#### A. Left-to-Right (LTR) Runs (`HB_DIRECTION_LTR`)
For LTR text, logical order and visual order are aligned. Cluster indices must be **monotonically non-decreasing**.
$$\forall i \in [0, N-2], \quad C(i) \le C(i+1)$$
*Example (Latin with `fi` ligature):*
* Input (Logical UTF-16): `'f'` (0), `'i'` (1), `'x'` (2)
* Output (Visual Glyphs): `[fi_glyph, x_glyph]`
* Cluster Progression: `[0, 2]` ($0 \le 2$, strictly non-decreasing).

#### B. Right-to-Left (RTL) Runs (`HB_DIRECTION_RTL`)
For RTL text, HarfBuzz reverses the buffer at the end of the shaping pipeline so that glyphs are positioned left-to-right for the rasterizer. Consequently, cluster indices in the final buffer must be **monotonically non-increasing**.
$$\forall i \in [0, N-2], \quad C(i) \ge C(i+1)$$
*Example (Arabic):*
* Input (Logical UTF-16): `Alef` (0), `Lam` (1), `Meem` (2)
* Output (Visual Glyphs, L-to-R): `[Meem_glyph, Lam_Alef_ligature]`
* Cluster Progression: `[2, 0]` ($2 \ge 0$, strictly non-increasing).

---

### 3. Cluster Merging Mechanics (Maintaining Monotonicity)
When OpenType features or complex script shapers (e.g., Indic, Myanmar, Khmer) reorder glyphs, naive cluster assignment would violate monotonicity. 

*Scenario:* Logical characters $A(0), B(1), C(2)$ are reordered visually to $C, A, B$. 
A naive cluster progression of `[2, 0, 1]` is **non-monotonic** and breaks Blink's binary search and text-slicing algorithms.

**The HarfBuzz Resolution (`hb_buffer_merge_clusters`):**
Whenever HarfBuzz detects a reordering or a multi-glyph substitution spanning non-adjacent characters, it merges the bounding clusters. All glyphs involved in the operation are assigned the **minimum** cluster index of the participating logical characters.

In the $C, A, B$ reordering scenario:
1. HarfBuzz merges clusters from index $0$ to $2$.
2. The minimum index in this span is $0$.
3. The resulting visual glyphs `[C, A, B]` are assigned clusters `[0, 0, 0]`.
4. Monotonicity ($0 \le 0 \le 0$) is preserved at the cost of intra-cluster cursor granularity.

---

### 4. Blink's `HB_BUFFER_CLUSTER_LEVEL` Configuration
HarfBuzz offers three cluster levels. Audit of `HarfBuzzShaper` confirms Blink operates using **`HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES`** (the HarfBuzz default) or **`HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS`** depending on specific segmentation contexts, while strictly avoiding `HB_BUFFER_CLUSTER_LEVEL_CHARACTERS`.

* **Why `CHARACTERS` is forbidden in Blink:** It disables cluster merging during reordering, resulting in non-monotonic cluster arrays.
* **Blink's UTF-16 Mapping:** Before shaping, Blink populates the `hb_buffer_t` using `hb_buffer_add_utf16` (or `add_latin1`). The initial cluster values fed to HarfBuzz are the exact UTF-16 code unit offsets relative to the start of the `ShapeResultRun` (or the parent `TextRun`).

---

### 5. Blink Engine Dependency on Monotonicity
In `ShapeResult.cpp` and `ShapeResultBuffer.cpp`, Blink relies on this monotonic progression for performance-critical layout operations:

1. **O(log N) Hit Testing (`OffsetForPosition`) & Caret Positioning (`PositionForOffset`):**
   Because the `HarfBuzzRunGlyphData` array inherits the monotonic cluster progression from HarfBuzz, Blink can execute binary searches (`std::lower_bound` / `std::upper_bound`) over the glyph array to map DOM character offsets to visual X-coordinates without scanning the entire run.
2. **Sub-run Slicing (`ShapeResult::SubRange`):**
   During line breaking (`NGLineBreaker`), Blink frequently slices a pre-shaped `ShapeResult` into multiple lines without re-shaping. It locates break opportunities by scanning for cluster boundaries (where $C(i) \neq C(i+1)$). Monotonicity guarantees that a slice between cluster $X$ and cluster $Y$ forms a contiguous slice of the underlying glyph array.
3. **Character Range Computation (`NumCharacters`):**
   The number of UTF-16 code units represented by a specific glyph cluster starting at visual index $i$ and ending at $j$ (where $C(i) = C(j)$) is calculated in $O(1)$ time by looking at the next distinct cluster:
   * **LTR:** $\text{Length} = C(j+1) - C(i)$ (or `run_end_index` $- C(i)$ if at the end of the buffer).
   * **RTL:** $\text{Length} = C(i-1) - C(i)$ (or `run_end_index` $- C(i)$ if at the start of the buffer).

### 6. Audit Verification & Edge Cases
Blink enforces cluster monotonicity via `DCHECK` assertions during `ShapeResult::InsertRun` and glyph population:

* **Buffer Overflow / Truncation Edge Case:** `HarfBuzzRunGlyphData` stores the cluster index in a 16-bit unsigned integer (`uint16_t character_index`). If a single `ShapeResultRun` exceeds $65,535$ characters, cluster indices would wrap around, violating monotonicity. 
  * *Mitigation:* Blink's `HarfBuzzShaper` actively segments massive text nodes into smaller sub-runs capped well below `std::numeric_limits<uint16_t>::max()` (typically capped at `kMaxCharactersPerRun = 32768`) before invoking `hb_shape()`, ensuring 16-bit cluster indices remain strictly monotonic.

**[END OF AUDIT REPORT - AGENT 341]**