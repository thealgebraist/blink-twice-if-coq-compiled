**AUDIT REPORT: Blink Text Engine**  
**AUDITOR:** Agent 348  
**SUBJECT:** Variation Selector Branching (VS15 vs. VS16 Presentation Resolution)  
**TARGET MODULE:** `third_party/blink/renderer/platform/fonts/`

---

### 1. Executive Summary
This audit details the control-flow branching inside Chromium’s Blink rendering engine when encountering Unicode Variation Selector-15 (**VS15**, `U+FE0E`, Text Presentation) and Variation Selector-16 (**VS16**, `U+FE0F`, Emoji Presentation). 

In Blink, presentation resolution is not deferred entirely to HarfBuzz. Instead, it is handled **pre-shaping** during the **Run Segmentation** and **Font Fallback** phases. VS15 and VS16 act as hard overrides that mutate the `FontFallbackPriority` of a character cluster, forcing the engine to branch into completely different font lookup cascades (monochrome system fonts vs. color emoji fonts).

---

### 2. Primary Branching Site: Run Segmentation
The earliest and most critical branch occurs during UTF-16 buffer tokenization in `RunSegmenter` and `SymbolsIterator`. Blink uses an Ragel-generated state machine (`unicode_emoji_scanner.c`) alongside ICU properties to group base characters with their variation selectors into indivisible grapheme clusters.

#### Module: `SymbolsIterator::Consume()`
When `SymbolsIterator` scans a text run, it evaluates the emoji properties of code points and peeks ahead for Variation Selectors.

```
[Input UTF-16 Buffer] 
       │
       ▼
[Base Character: Emoji_Presentation OR Emoji]
       │
       ├──► Peek Next Code Point == U+FE0E (VS15) ──► Branch: TEXT_PRESENTATION
       │
       ├──► Peek Next Code Point == U+FE0F (VS16) ──► Branch: EMOJI_PRESENTATION
       │
       └──► Peek Next Code Point == None/Other   ──► Branch: DEFAULT_PRESENTATION
```

#### The State Resolution (`FontFallbackPriority`)
Depending on the branch taken above, the segmenter assigns an explicit `FontFallbackPriority` enum value to the `RunSegmenterRange`:

1. **The VS15 Branch (`U+FE0E`):**
   * **Condition:** Base character is `Emoji` + followed by `U+FE0E`.
   * **Action:** Sets priority to `FontFallbackPriority::kText`.
   * **Effect:** Even if the base character has the Unicode property `Emoji_Presentation=Yes` (e.g., `U+231A` WATCH ⌚), VS15 strips its emoji priority. It is merged into the standard text run.

2. **The VS16 Branch (`U+FE0F`):**
   * **Condition:** Base character is `Emoji` + followed by `U+FE0F`.
   * **Action:** Sets priority to `FontFallbackPriority::kEmojiEmoji`.
   * **Effect:** Even if the base character has `Emoji_Presentation=No` (e.g., `U+2665` BLACK HEART SUIT ♥), VS16 upgrades the cluster, isolating it into a distinct emoji-priority segment.

---

### 3. Secondary Branching Site: Font Fallback Cascade
Once `HarfBuzzShaper` receives the segmented runs, it invokes `FontFallbackIterator` to resolve a `SimpleFontData` (physical font face) capable of rendering the cluster. The `FontFallbackPriority` determined in Phase 2 drives the branching in `FontFallbackList` and `FontCache`.

#### Module: `FontFallbackIterator::Next()` & `FontFallbackMap`

| Branch Feature | VS15 (`kText`) | VS16 (`kEmojiEmoji`) |
| :--- | :--- | :--- |
| **Primary Lookup** | CSS `font-family` list | CSS `font-family` list (checked for color tables) |
| **System Fallback** | `FontCache::GetFallbackFontForCharacter` (Standard) | `FontCache::GetFallbackFontForCharacter` (Emoji Preferential) |
| **Target Font Format** | Outline (`glyf`, `CFF`) | Color (`CBDT/CBLC`, `COLR/CPAL`, `sbix`, `SVG`) |

#### A. Execution of the VS15 (`kText`) Branch:
1. Blink iterates through the author-specified CSS `font-family` list.
2. It calls `FontDataForCharacter()` passing the base character and `U+FE0E`.
3. **Crucial Check:** If an author explicitly put an Emoji font in the CSS stack, Blink checks if the font has a specific `cmap` Format 14 entry for `Base + VS15`. If not, and the font is purely a color emoji font, Blink **rejects** the font during fallback to prevent rendering a color glyph when text was requested.
4. System fallback queries the OS (DirectWrite, CoreText, FontConfig) requesting a standard monochrome typeface (e.g., *Segoe UI Symbol*, *Apple Symbols*, *Noto Sans Symbols*).

#### B. Execution of the VS16 (`kEmojiEmoji`) Branch:
1. Blink bypasses standard text fonts in the CSS list unless they explicitly support the `U+FE0F` variation sequence or contain color tables.
2. If the CSS stack fails to provide an emoji presentation, `FontFallbackIterator` immediately branches to `FontCache::GetDWriteFallbackFamily` (Windows) or equivalent platform-specific emoji routing.
3. Blink explicitly loads the platform's default color emoji font (*Segoe UI Emoji*, *Apple Color Emoji*, *Noto Color Emoji*).

---

### 4. Tertiary Branching Site: HarfBuzz `cmap` Subtable Resolution
Once the correct font is selected by Blink’s fallback cascade, the cluster (`Base + VS15/VS16`) is passed to `HarfBuzzShaper`. The final branching occurs inside HarfBuzz's OpenType `cmap` table lookup (`hb_ot_get_glyph`).

Blink configures `HarfBuzzFace` callbacks (`HarfBuzzGetGlyph`) to handle Variation Selectors via **OpenType `cmap` Format 14 (Unicode Variation Sequences)**:

```cpp
// Conceptual flow in HarfBuzzFace / Skia Font Host
hb_bool_t GetVariationGlyph(hb_font_t* font, hb_codepoint_t unicode, hb_codepoint_t variation_selector, hb_codepoint_t* glyph) {
    // 1. Query Format 14 subtable for exact (unicode + variation_selector) match.
    if (FontHasCmapFormat14Match(unicode, variation_selector, glyph)) {
        return true; // Branch A: Explicit Variant Glyph Found
    }
    
    // 2. Fallback to standard Format 4 / Format 12 cmap lookup for base character only.
    if (FontHasNominalGlyph(unicode, glyph)) {
        return true; // Branch B: Default Glyph Used (VS ignored at glyph level)
    }
    
    return false; // Branch C: .notdef (Triggers Blink next font fallback)
}
```

* **Why this matters for auditing:** Most system emoji fonts (like *Noto Color Emoji*) **do not** actually use `cmap` Format 14 for `U+FE0F`. They simply map the base character directly to the color glyph in Format 12. Because Blink *already* branched to the Emoji font in Phase 2/3, HarfBuzz takes **Branch B** (Nominal Glyph) and successfully renders the color emoji, dropping the `U+FE0F` silently without rendering a `.notdef` (tofu) box.
* Conversely, hybrid fonts (like *Segoe UI Emoji* on Windows, which contains both monochrome outlines and `COLR/CPAL` layers) rely heavily on **Branch A** (`cmap` Format 14) to switch between the monochrome glyph ID and the color glyph ID within the exact same font file.

---

### 5. Identified Edge Cases & Audit Anomalies

1. **Invalid Variation Sequences:**
   If a user appends `VS15` or `VS16` to a code point that is **not** defined in Unicode's `emoji-variation-sequences.txt` (e.g., `A` + `U+FE0F`), `unicode_emoji_scanner.c` will **not** trigger the `kEmojiEmoji` branch. It remains `kText`, and HarfBuzz strips the stray variation selector via `hb_unicode_is_variation_selector` so it does not render as `.notdef`.
2. **`font-variant-emoji` CSS Override:**
   With the introduction of the CSS `font-variant-emoji` property (`text | emoji | unicode`), Blink inserts an override branch *before* `SymbolsIterator` defaults. However, explicit inline `VS15` or `VS16` code points in the DOM text node **always trump** the CSS `font-variant-emoji` property per the CSS Fonts Module Level 4 specification.
3. **ZWJ Sequence Pollution:**
   In Zero-Width Joiner (`U+200D`) sequences, a single `VS16` typically upgrades the entire ZWJ cluster to `kEmojiEmoji`. However, if a `VS15` (`U+FE0E`) is injected mid-ZWJ-sequence, Blink's Ragel scanner breaks the emoji cluster token, causing the sequence to shatter into separate fallback runs, breaking the ligature.

**END OF AUDIT REPORT — AGENT 348**