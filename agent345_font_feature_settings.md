**AUDIT REPORT: BLINK RENDERING ENGINE**
**Subject:** OpenType Font Feature Settings (`font-feature-settings`)
**Auditor:** Agent 345
**Status:** Active Review

---

### 1. Executive Summary
This audit details the internal mechanisms utilized by the Blink rendering engine (and its underlying text shaping engine, HarfBuzz) to evaluate OpenType feature tag equality and manage the pipeline for feature activation. 

---

### 2. Tag Equality (Parsing and Normalization)

In Blink, OpenType feature tags are defined by the CSS `font-feature-settings` property as a 4-character ASCII string. To optimize comparisons during style recalculation and text shaping, Blink converts these strings into 32-bit unsigned integers (`uint32_t` / `hb_tag_t`).

#### 2.1. Byte-Level Representation
A valid tag must consist of 4 ASCII characters within the printable range (`0x20` to `0x7E`). Blink converts the 4 characters into a big-endian 32-bit integer using the following bit-shifting logic:

$$\text{Tag} = (c_0 \ll 24) \mid (c_1 \ll 16) \mid (c_2 \ll 8) \mid c_3$$

For example, the standard ligature tag `"liga"` is stored in memory as `0x6c696761`.

#### 2.2. Strict Equality Rules
When Blink evaluates `FontFeatureSettings` objects for equality (e.g., to determine if a style change requires a layout or shaping invalidation), the following rules apply:

*   **Case Sensitivity:** Tag comparison is strictly case-sensitive. `"smcp"` (`0x736d6370`) $\neq$ `"SMCP"` (`0x534d4350`). Invalid casing is rejected or fails to match tables in the font binary.
*   **Padding:** Tags shorter than 4 characters in the specification are padded with spaces (`0x20`), though CSS syntax strictly requires 4 characters to be declared by the author.
*   **Object Equality (`FontFeature`):** Two `FontFeature` instances in Blink (`platform/fonts/opentype/font_settings.h`) are considered equal if and only if:
    $$\text{Feature}_A == \text{Feature}_B \iff (\text{Tag}_A == \text{Tag}_B) \land (\text{Value}_A == \text{Value}_B)$$

---

### 3. Feature Activation Pipeline

Feature activation in Blink is a multi-tiered cascade. When a text run is sent to `HarfBuzzShaper`, features are aggregated and resolved in a strict order of precedence. If the same tag is declared multiple times, **later declarations overwrite earlier ones**.

#### 3.1. The Precedence Cascade (Lowest to Highest)
1.  **HarfBuzz / Script Defaults:** Features required by the script's shaping engine (e.g., `ccmp`, `locl`, `isol`, `medi`, `fina` for Arabic; `liga` and `clig` for Latin).
2.  **Font-Variant Properties:** High-level CSS properties (`font-variant-ligatures`, `font-variant-caps`, `font-variant-numeric`, etc.) are translated into low-level OpenType tags.
3.  **CSS `font-feature-settings`:** Low-level author overrides declared in CSS.
4.  **Internal Engine Overrides:** Blink forces specific features based on layout context (e.g., disabling `liga` and `clig` if `letter-spacing` is non-zero).

#### 3.2. Activation States (Value Resolution)
Every parsed tag is paired with an integer value determining its activation state:

*   **Deactivation (`0` or `off`):** Passes `0` to HarfBuzz. If the feature was enabled by default (like `"liga"`), this explicitly disables the lookup in the `GSUB`/`GPOS` tables.
*   **Boolean Activation (`1` or `on`):** Passes `1` to HarfBuzz. When a value is omitted in CSS (e.g., `font-feature-settings: "smcp";`), Blink implicitly assigns a value of `1`.
*   **Indexed Activation (`> 1`):** Used for mutually exclusive alternate selections (e.g., `"swsh" 2`, `"salt" 3`, or Character Variants `"cv01"` through `"cv99"`). HarfBuzz uses this integer as a 1-based index to select the specific glyph from the alternate array in the `GSUB` Lookup Type 3 table.

#### 3.3. Conflict Resolution within `font-feature-settings`
If a single CSS declaration contains duplicate tags with different values, Blink resolves them sequentially from left to right:

```css
/* Audit Test Case */
.target-text {
    font-feature-settings: "liga" 0, "dlig" 1, "liga" 1;
}
```
*   **Step 1:** `"liga"` (`0x6c696761`) is appended to the `hb_feature_t` vector with value `0`.
*   **Step 2:** `"dlig"` (`0x646c6967`) is appended with value `1`.
*   **Step 3:** `"liga"` (`0x6c696761`) is appended with value `1`.
*   **Shaping Execution:** HarfBuzz processes the array sequentially. The second `"liga"` overrides the first. Standard ligatures remain **Active**.

---

### 4. Anomalies and Edge Cases (Audit Notes)

*   **Shape Cache Keying:** Blink caches shaped text runs (`ShapeResult`) to optimize performance. The `FontFeatureSettings` list is part of the `FontDescription` hash key. However, two lists with identical features in *different orders* (e.g., `"smcp", "zero"` vs `"zero", "smcp"`) will generate **different hash keys**, resulting in a cache miss despite producing identical visual output.
*   **Font Synthesis vs. Features:** If `"smcp"` is activated, Blink disables synthetic small-caps generation, delegating entirely to the font's `GSUB` table. If the font lacks the `"smcp"` tag, activation silently fails, and text renders in standard lowercase.

**End of Report.** 
*Agent 345 signing off.*