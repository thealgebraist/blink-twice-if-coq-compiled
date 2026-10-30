**AUDIT REPORT: Blink Layout & Shaping Engine**  
**Auditor:** Agent 343  
**Subject:** Conditional Application of `word-spacing` on Space Codepoints  
**Target Subsystems:** `third_party/blink/renderer/platform/fonts/shaping/` and `third_party/blink/renderer/core/layout/inline/`

---

### 1. Executive Summary
In the Chromium Blink rendering engine, CSS `word-spacing` is not applied indiscriminately to all whitespace characters. Its application is strictly conditional, governed by CSS Text Module Level 3 specifications, Unicode properties, and font-shaping state machines (HarfBuzz integration). 

Below is the technical breakdown of the conditions, eligible codepoints, and pipeline stages that dictate how and when `word-spacing` mutates glyph advances.

---

### 2. Eligible Space Codepoints
Blink evaluates `word-spacing` eligibility through character classification functions located in `platform/wtf/text/character_names.h` and `platform/fonts/shaping/harfbuzz_shaper.cc`.

#### A. Target Codepoints (Word Separators)
By default, Blink only applies `word-spacing` to characters defined by the CSS specification as "word-separator characters":
*   **`U+0020` (SPACE):** The primary target.
*   **`U+00A0` (NO-BREAK SPACE - NBSP):** Treated identically to `U+0020` for `word-spacing` purposes, despite forbidding line breaks.
*   **`U+1361` (ETHIOPIC WORDSPACE):** Script-specific word separator.
*   **`U+10100`, `U+10101` (AEGEAN WORD SEPARATOR LINE/DOT):** Ancient script separators.
*   **`U+1039F` (UGARITIC WORD DIVIDER):** Ancient script separator.
*   **`U+1091F` (PHOENICIAN WORD SEPARATOR):** Ancient script separator.

#### B. Explicitly Excluded Whitespace Codepoints
The following whitespace characters **do not** trigger `word-spacing` in Blink under standard conditions:
*   **Fixed-Width Spaces (`U+2000` through `U+200B`):** En Quad, Em Quad, En Space, Em Space, Three-Per-Em, Four-Per-Em, Six-Per-Em, Figure Space, Punctuation Space, Thin Space, Hair Space, and Zero-Width Space (ZWSP). *Condition: Authors use these for explicit typographic measurement; mutating them via `word-spacing` violates layout intent.*
*   **`U+3000` (IDEOGRAPHIC SPACE):** Treated as a full-width CJK ideograph rather than a word separator.

---

### 3. Conditional Application Matrix

For an eligible codepoint (e.g., `U+0020`) to actually receive the `word-spacing` pixel offset, it must survive five pipeline conditions:

#### Condition 1: The Whitespace Collapsing Phase (`NGInlineItemsBuilder`)
Before shaping occurs, the LayoutNG inline builder processes raw DOM strings based on the `white-space` CSS property (`normal`, `nowrap`, `pre`, `pre-wrap`, `pre-line`, `break-spaces`).
*   **Collapsed Spaces:** If `white-space: normal`, a sequence of `U+0020` characters is collapsed into a single `U+0020`. `word-spacing` is applied **once** to the surviving character, not multiplied by the raw DOM character count.
*   **Preserved Spaces:** If `white-space: pre` or `pre-wrap`, every surviving `U+0020` in the sequence receives the `word-spacing` offset individually.
*   **Trimmed Spaces:** Spaces at the beginning or end of a line that are collapsed/removed during line-breaking (`NGLineBreaker`) have their advances zeroed out; `word-spacing` is stripped.

#### Condition 2: Control Character Transformation
*   **`U+0009` (TAB):** Under `white-space: normal`, tabs are converted to `U+0020` during `NGInlineItemsBuilder` normalization. **Condition:** Once converted to `U+0020`, they **do** receive `word-spacing`. However, if `white-space: pre` is active, the character remains a Tab, its width is calculated via `TabSize`, and `word-spacing` is **bypassed**.
*   **`U+000A` (LINE FEED):** If collapsed into a space (`white-space: normal`), it becomes `U+0020` and **receives** `word-spacing`. If preserved as a forced break, it does not.

#### Condition 3: The Shaping Pipeline (`ShapeResultSpacing`)
Blink applies spacing post-HarfBuzz shaping or during glyph advance accumulation via the `ShapeResultSpacing` class.
```cpp
// Conceptual representation of ShapeResultSpacing::ComputeSpacing
float spacing = 0;
if (Character::IsWordSeparator(character)) {
    spacing += word_spacing_;
}
spacing += letter_spacing_; // Note: letter-spacing applies to spaces too!
```
*   **Additive Condition:** If both `letter-spacing` and `word-spacing` are defined, a `U+0020` codepoint receives **both** offsets (`advance += letter_spacing + word_spacing`).
*   **Negative Spacing Clamp:** If `word-spacing` is a large negative value, Blink allows the space glyph's advance to become negative (causing words to overlap), as required by CSS specs. It is not clamped to zero at the glyph level.

#### Condition 4: Font Features & Ligatures
If the active `FontDescription` includes OpenType features (e.g., `liga`, `calt`) where a `U+0020` character is consumed into a single multi-character ligature glyph with adjacent letters:
*   **Condition:** HarfBuzz merges the cluster. If the space no longer exists as an independent glyph cluster representable in the `ShapeResult` run, `ShapeResultSpacing` cannot target the space codepoint independently, and `word-spacing` fails to apply to that specific instance.

#### Condition 5: Soft Hyphens & Zero-Width Joiners
*   `U+00AD` (SOFT HYPHEN), `U+200C` (ZWNJ), and `U+200D` (ZWJ) are explicitly filtered out before `IsWordSeparator` checks. They never receive `word-spacing`.

---

### 4. Edge Case Audit Findings

1.  **Percentage Values (`word-spacing: 50%`):** 
    *   *Status:* Blink parses percentage values depending on CSS Text 4 flags, resolving the percentage against the advance width of the current font's `U+0020` glyph. If the font lacks a `U+0020` glyph and synthesizes it, the fallback metric is used as the base for the conditional multiplier.
2.  **Text Justification (`text-align: justify`):** 
    *   *Status:* Justification operates in `NGInlineLayoutAlgorithm` *after* `word-spacing` has been applied. The base advance of `U+0020` (already mutated by `word-spacing`) is further expanded by the justification opportunity distributor.
3.  **Bidi Reordering:** 
    *   *Status:* `word-spacing` is bound to the logical character index within the `ShapeResult`, meaning visual reordering via the Unicode Bidirectional Algorithm (UBA) moves the space and its `word-spacing` advance together without corruption.

**Audit Conclusion:** Blink's conditional handling of `word-spacing` on space codepoints is compliant with CSS Text Level 3. The separation between DOM-level character collapsing (`NGInlineItemsBuilder`) and glyph-level metric mutation (`ShapeResultSpacing`) prevents double-application bugs. 

*End of Report — Agent 343.*