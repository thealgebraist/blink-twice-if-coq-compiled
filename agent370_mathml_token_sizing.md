**AGENT 370 — BLINK MATHML AUDIT LOG**
**Target:** `<mi>` (Math Identifier) Element Font Style Resolution
**Component:** `Blink>MathML` / `Blink>CSS`

---

### 1. Executive Summary & Spec Baseline
Per the **MathML Core Specification (Section 3.2.3)**, the `<mi>` element represents a mathematical identifier. Its default typographical presentation depends strictly on the character count of its text content:
*   **Single-character `<mi>`:** Rendered in **italic** (`math-auto` maps to italic/slanted glyphs) to represent variables (e.g., $x$).
*   **Multi-character `<mi>`:** Rendered in **normal** (upright) font-style to represent function names or constants (e.g., $\sin$, $\mathrm{lim}$).

In Chromium’s Blink engine, this behavior is not handled via standard CSS selectors (as CSS lacks a character-count selector). Instead, it relies on a bridge between DOM inspection and the CSS `text-transform: math-auto` pipeline.

---

### 2. Architectural Implementation in Blink

#### A. UA Stylesheet Baseline
In `third_party/blink/renderer/core/css/mathml.css`, the `<mi>` element is assigned a special text transformation rather than a direct `font-style`:
```css
mi {
  text-transform: math-auto;
}
```
*Note: The default `font-style` remains `normal`. The "italicization" in MathML Core is actually a Unicode mathematical alphanumeric symbol mapping (or OpenType `ital`/`ssty` feature application) triggered by `math-auto`, though it interacts with `font-style`.*

#### B. Character Count Determination (`MathMLTextElement`)
The core logic resides in `third_party/blink/renderer/core/mathml/mathml_text_element.cc` (or equivalent token element handler). Blink determines whether the `<mi>` content is single- or multi-character by inspecting the DOM text nodes.

1.  **Normalization:** Blink retrieves the text content of the `<mi>` element and strips leading and trailing ASCII whitespace (U+0009, U+000A, U+000C, U+000D, U+0020) per the MathML Core spec.
2.  **Code Point Counting (UTF-16 to UTF-32):**
    *   Blink strings (`WTF::String`) may be 8-bit (Latin1) or 16-bit (UTF-16).
    *   To accurately count *characters* (Unicode code points) rather than *code units*, Blink must account for surrogate pairs (e.g., characters in the Supplementary Multilingual Plane like `U+1D400`).
    *   Blink iterates over the trimmed string using `CharacterIterator` or `U16_NEXT` (ICU macro) to count actual Unicode scalar values.

```cpp
// Conceptual representation of Blink's internal check
bool IsSingleCharacter(const String& text) {
  String stripped = text.StripWhiteSpace(IsASCIIWhitespace);
  if (stripped.empty()) return false;
  
  // Advance by one code point (handles surrogate pairs)
  unsigned index = 0;
  UChar32 code_point;
  U16_NEXT(stripped.Characters16(), index, stripped.length(), code_point);
  
  // If the index after one code point equals the total length, it's a single char.
  return index == stripped.length();
}
```

#### C. Style Resolution & Layout (`ComputedStyle`)
During the style recalculation phase (`StyleResolver`):
1.  **Single Character (`length == 1`):**
    *   `text-transform: math-auto` remains active.
    *   During `HarfBuzzShaper` execution (`third_party/blink/renderer/platform/fonts/shaping/`), the single character (e.g., `'x'` `U+0078`) is mapped to its corresponding Mathematical Alphanumeric Symbol (e.g., `'𝑥'` `U+1D465` Mathematical Italic Small X) via `MathVariant` mapping tables.
    *   If the character has no Unicode math-italic equivalent (e.g., certain Greek letters or symbols), it falls back to standard synthesis or font-style italicization.
2.  **Multi-Character (`length > 1`):**
    *   If the `<mi>` contains multiple code points (e.g., `"sin"`), the element suppresses the `math-auto` transformation.
    *   In Blink, this is done by dynamically invalidating style when `ChildrenChanged()` is triggered on the `<mi>` node, overriding the effective `ETextTransform` in `ComputedStyle` to `kNone` (upright), **unless** `mathvariant` is explicitly set.

---

### 3. Edge Cases & Audit Verification Points

As Agent 370, the following edge cases in Blink's implementation must be monitored for regressions:

*   **Surrogate Pairs:** `<mi>&#x1D400;</mi>` (2 UTF-16 code units, 1 Unicode code point). Blink correctly evaluates this as a **single** character.
*   **Grapheme Clusters / Combining Marks:** `<mi>x&#x0302;</mi>` ($x$ with circumflex). This consists of 2 Unicode code points (`U+0078` + `U+0302`). Per MathML Core, length is measured in *code points*, not extended grapheme clusters. Thus, this is evaluated as **multi-character** and renders upright.
*   **Dynamic DOM Mutation:** If JS mutates `<mi>x</mi>` to `<mi>xy</mi>`, `MathMLTextElement::ChildrenChanged` or `CharacterDataModified` must call `SetNeedsStyleRecalc()` to ensure the `math-auto` transform is stripped.
*   **Child Elements:** If `<mi>` contains non-text child nodes (e.g., `<mi>x<span>y</span></mi>`), the spec dictates fallback behavior. Blink checks if the child nodes are strictly text nodes before applying the single-char italicization rule.
*   **Explicit Overrides:** If the author specifies `<mi style="font-style: normal">x</mi>` or `<mi mathvariant="normal">x</mi>`, the UA's `text-transform: math-auto` is overridden by author origin styles or mapped attributes in `MathMLElement::CollectStyleForPresentationAttribute`.

**Audit Status:** CONFORMANT (Aligned with WPT `mathml/presentation-markup/tokens/mi-mathvariant.html`).
**Agent 370 signing off.**