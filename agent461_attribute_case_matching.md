**Agent 461 Reporting.** 
**Audit Target:** Chromium/Blink HTML & DOM Attribute Matching Subsystem.
**Subject:** ASCII Case-Folding Equivalence.

In the Blink rendering engine, attribute matching—spanning DOM API queries, HTML parsing, and CSS selector evaluation—strictly adheres to the WHATWG Infra and HTML specifications regarding **ASCII case-insensitivity**. Full Unicode case-folding is explicitly bypassed in standard attribute matching for both performance optimization and specification compliance.

Below is the technical breakdown of how Blink implements and enforces ASCII case-folding equivalence.

---

### 1. The Mathematical Definition
Blink defines ASCII case-folding equivalence by mapping all characters in the `ASCII upper alpha` range to the `ASCII lower alpha` range while leaving all other code points (including non-ASCII Unicode characters) untouched.

*   **Target Range:** `0x41` (`'A'`) through `0x5A` (`'Z'`).
*   **Transformation:** $C_{\text{folded}} = C \lor \text{0x20}$ (Bitwise OR with `00100000`).
*   **Resulting Range:** `0x61` (`'a'`) through `0x7A` (`'z'`).

Code points outside `0x41–0x5A` (such as `'É'` at `0xC9` or `'ß'` at `0xDF`) are evaluated by their exact byte values. Consequently, under Blink's ASCII case folding, `"resume"` matches `"RESUME"`, but `"résumé"` **does not** match `"RÉSUMÉ"`.

---

### 2. Core Implementation in WTF (Web Template Framework)
Blink relies on `WTF::String`, `WTF::AtomicString`, and `WTF::StringView` for text representation. The core comparison logic resides in `third_party/blink/renderer/platform/wtf/text/`.

#### Bitwise Optimization (`ASCIIFastPath.h`)
To avoid branching (which causes CPU pipeline stalls), Blink uses a bitwise fast path for ASCII case conversion:
```cpp
template <typename CharacterType>
inline CharacterType ToASCIILower(CharacterType c) {
  return c | ((c >= 'A' && c <= 'Z') << 5);
}
```
When comparing strings via `EqualIgnoringASCIICase()`, Blink processes characters in machine-word chunks (32-bit or 64-bit) when memory alignment permits, falling back to byte-by-byte evaluation using lookup tables (`kASCIICaseFoldTable`) or the bitwise operation above.

#### String Representation Parity
Blink optimizes memory by storing strings as either 8-bit (`LChar`, Latin-1) or 16-bit (`UChar`, UTF-16). `EqualIgnoringASCIICase` handles three permutations:
1.  **`LChar` vs `LChar`:** Fast-path byte comparison.
2.  **`UChar` vs `UChar`:** 16-bit word comparison (ignoring high bytes unless they are non-zero, which automatically fails the `0x41-0x5A` check).
3.  **`LChar` vs `UChar`:** Mixed-width comparison. Since Latin-1 (`0x00–0xFF`) is a strict subset of UTF-16 (`0x0000–0x00FF`), Blink zero-extends the `LChar` to 16 bits and applies the standard ASCII mask. 

*Audit Note:* In Latin-1 (`LChar`), characters like `0xC0` (`À`) and `0xE0` (`à`) also differ by `0x20`. A naive `c | 0x20` without bounds checking would falsely equate them. Blink’s bounds check `(c >= 'A' && c <= 'Z')` prevents this Latin-1 collision bug.

---

### 3. Execution Contexts in Blink

#### A. HTML Parser & `AtomicString` Interning
When the `HTMLTokenizer` parses an HTML document, attribute **names** are folded to ASCII lowercase *at the tokenization stage*. 
*   `<div DATA-FOO="Bar">` is tokenized as attribute name `data-foo` and value `"Bar"`.
*   The name is interned into the `AtomicStringTable`.
*   Subsequent DOM lookups (e.g., `element.getAttribute('DATA-FOO')`) will first ASCII-lowercase the query string if the target `Element` is in an HTML namespace, reducing the lookup to a $O(1)$ pointer comparison between `AtomicString` instances.

#### B. XML/SVG Namespaces (The Exception)
If the `Document` or `Element` is in an XML/SVG/MathML namespace (and not an HTML integration point), Blink bypasses ASCII case-folding for `getAttribute()` and `hasAttribute()`, requiring exact byte-for-byte `AtomicString` pointer equivalence, except for mapped attributes defined in the SVG spec.

#### C. CSS Attribute Selectors (`SelectorChecker.cc`)
When evaluating CSS selectors like `[attr=val]`, Blink’s `SelectorChecker` determines case-sensitivity based on two factors:
1.  **Default HTML Rules:** Certain attribute *values* (like `type`, `align`, `charset`, `hreflang`) are hardcoded in Blink (`HTMLDocument::IsCaseInsensitiveAttribute`) to be matched using `EqualIgnoringASCIICase`. Others (like `id`, `class`, `data-*`) are case-sensitive by default.
2.  **The `i` and `s` Modifiers:** 
    *   `[data-foo="VAL" i]` forces Blink to invoke `EqualIgnoringASCIICase()` on the attribute value, regardless of the attribute type or namespace.
    *   `[type="TEXT" s]` forces exact case-sensitive matching (`operator==`), overriding the default HTML case-insensitivity for the `type` attribute.

---

### 4. Security & Edge-Case Audit Vectors

As Agent 461, I flag the following areas where ASCII case-folding equivalence intersects with security boundaries:

1.  **The Kelvin Sign (`U+212A`) & Latin Small Letter Dotless I (`U+0131`):**
    In full Unicode case folding, `U+212A` (K) folds to `0x6B` (`'k'`), and `U+0130` (`İ`) folds to `0x69` (`'i'`). Because Blink strictly uses *ASCII* case-folding for attributes, `<script src="..."></script>` vs `<scrİpt>` or `onclK="..."` will **never** fold to `"script"` or `"onclick"`. If an external sanitizer uses *Unicode* case-folding while Blink uses *ASCII* case-folding (or vice versa), XSS sanitizer bypasses occur. Blink is compliant here; the risk lies in upstream WAFs/sanitizers.
2.  **`LChar` Sign-Extension Bugs:**
    In C++, if `LChar` is defined as a signed `char` instead of `unsigned char` (`uint8_t`), characters `>= 0x80` become negative, potentially corrupting range checks if `< 'A'` is evaluated improperly. Blink mitigates this by strictly typing `LChar` as `unsigned char`.
3.  **Quirks Mode (`Document::InQuirksMode()`):**
    In Quirks Mode, class and ID selectors (`.foo`, `#bar`) fall back to `EqualIgnoringASCIICase`. However, `[id="bar"]` (as an attribute selector) remains case-sensitive unless the `i` flag is supplied. Blink correctly maintains this distinction in `SelectorChecker`.

**Audit Conclusion:** Blink's implementation of ASCII case-folding equivalence is specification-compliant, memory-safe regarding `LChar`/`UChar` width disparities, and immune to Unicode-to-ASCII collision vectors. 

**Agent 461 signing off.**