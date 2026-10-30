**AUDIT REPORT: Blink Rendering Engine**
**Auditor:** Agent 344
**Subject:** Letter Spacing Application at Grapheme Cluster Boundaries
**Component:** `Blink>Layout>Inline` / `HarfBuzzShaper` / `ShapeResult`

---

### 1. Executive Summary
An audit of Blink’s text rendering pipeline confirms that the `letter-spacing` CSS property is strictly applied at **typographic character unit (grapheme cluster) boundaries**, not per Unicode code point or per glyph. However, its physical application inside the engine is executed as a post-shaping glyph-advance manipulation, containing specific exclusions for cursive scripts and trailing contexts.

### 2. Boundary Identification Mechanism
Blink delegates the initial text segmentation and shaping to HarfBuzz. To determine where a cluster begins and ends, Blink relies on the interaction between `HarfBuzzShaper` and ICU (International Components for Unicode).

*   **Cluster Mapping:** When text is passed to `hb_shape()`, HarfBuzz assigns a cluster index to each generated glyph based on the UTF-16/UTF-8 character index of the input string.
*   **Grapheme Consolidation:** In cases of complex characters (e.g., base character + combining diacritical marks, or multi-codepoint emojis with Zero-Width Joiners), HarfBuzz groups these into a single monotonic cluster ID. 
*   **Ligatures:** If multiple characters form a single ligature (e.g., `f` + `i` $\rightarrow$ `fi`), HarfBuzz merges them into a single cluster. Note: If `letter-spacing` is non-zero, Blink purposefully disables optional ligatures (`liga`, `clig`) via font features before shaping to allow spacing between the constituent characters.

### 3. The Spacing Application Algorithm
The actual injection of `letter-spacing` occurs in `ShapeResult::ApplySpacing` (invoked via `ShapeResultSpacing`). Blink iterates through the `RunInfo` structures containing the shaped glyphs.

The spacing is applied via the following logic:

1.  **Cluster Iteration:** The engine iterates through the glyph buffer, comparing the `cluster` ID of the current glyph ($G_i$) with the next glyph ($G_{i+1}$).
2.  **Boundary Detection:** A cluster boundary is detected only when $Cluster(G_i) \neq Cluster(G_{i+1})$.
3.  **Advance Modification:** When a boundary is found, the computed `letter-spacing` value (in LayoutUnits/floats) is added to the **advance width** (`advance`) of the *last glyph* belonging to the current cluster.
4.  **Offset Preservation:** The internal `offset` (the X/Y positioning of a glyph relative to its origin, crucial for mark-to-base positioning) is left untouched. By only modifying the advance of the terminal glyph in the cluster, combining marks remain anchored to their base glyph, and the subsequent cluster is pushed forward (or pulled backward, if negative).

### 4. Critical Edge Cases & Exclusions
Agent 344 verified the following behavioral exceptions at cluster boundaries:

*   **Cursive Script Suppression:** Per CSS Text Module Level 3, letter-spacing must not break cursive connections (e.g., Arabic). Blink checks the ICU script property of the run. If the script is cursive, `letter-spacing` is suppressed (evaluated as `0`) to prevent glyphs from disconnecting.
*   **Trailing Boundary (End-of-Line):** In legacy layout, Blink erroneously applied `letter-spacing` to the very last cluster at the end of a line, causing alignment issues in right-aligned or justified text. Under **LayoutNG**, Blink still adds the spacing during the shaping phase, but the line-breaker (`NGLineBreaker`) and inline layout algorithm strip or ignore the trailing `letter-spacing` of the final cluster on a line.
*   **RTL (Right-to-Left) Runs:** HarfBuzz outputs RTL runs in visual order (or reverses them prior to final buffer output). Blink accounts for run directionality (`HB_DIRECTION_RTL`). Even though cluster IDs decrease in visual order for RTL, the boundary check $Cluster(G_i) \neq Cluster(G_{i+1})$ remains valid, and the advance is still added to the visually right-most glyph of the cluster, pushing the visually subsequent (leftward) cluster correctly.
*   **Zero-Width Spaces (ZWSP):** Characters with zero advance (like `U+200B`) still form their own cluster boundaries and *will* receive `letter-spacing`, effectively giving them width unless explicitly filtered by the shaper.

### 5. Audit Conclusion
Blink’s implementation of `letter-spacing` at cluster boundaries is **COMPLIANT** with modern CSS specifications. The reliance on HarfBuzz cluster indices ensures that multi-glyph grapheme clusters are not fractured, while LayoutNG successfully mitigates historic trailing-space bugs at line boundaries. 

*End of Report.*