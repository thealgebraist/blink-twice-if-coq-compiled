**AUDIT LOG: AGENT 462**
**TARGET:** Chromium Blink Engine (`third_party/blink/renderer/core/html/custom/`)
**SUBJECT:** Custom Element Registration — Hyphen Validation Requirement

---

### 1. Executive Summary
During the `customElements.define(name, constructor, options)` lifecycle, Blink enforces the WHATWG HTML specification for **Valid Custom Element Names**. The core structural invariant of this validation is the **mandatory inclusion of at least one U+002D HYPHEN-MINUS (`-`) character**, coupled with strict placement and exclusion rules to ensure forward compatibility with standard HTML/SVG/MathML parsing.

### 2. Specification Invariants (The Hyphen Rule)
According to the EBNF grammar for `PotentialCustomElementName`, a valid name must adhere to the following constraints regarding the hyphen:

1.  **Mandatory Presence:** The string must contain at least one `-` (U+002D). 
    *   *Rationale:* Prevents namespace collisions with future standard HTML tags, which the W3C/WHATWG guarantees will never contain hyphens (with historical exceptions handled via blocklists).
2.  **Leading Character Constraint:** The hyphen **cannot** be the first character. The name must strictly begin with a lowercase ASCII alpha character (`[a-z]`, U+0061 to U+007A).
3.  **Trailing/Consecutive Constraints:** None. A valid custom element name *may* end with a hyphen (e.g., `<my-element->`) and *may* contain consecutive hyphens (e.g., `<my--element>`).

### 3. Blink Implementation Details
In Blink, this validation is executed synchronously during the `CustomElementRegistry::define` call, specifically delegated to the `CustomElement::IsValidName` utility method.

**Source Location:** `third_party/blink/renderer/core/html/custom/custom_element.cc` (and `custom_element_descriptor.h`)

#### Validation Pipeline:
1.  **Fast-Path Hyphen Check:** 
    Blink first checks if the `AtomicString` contains a hyphen (`name.find('-') != kNotFound`) and verifies that the first character is within the `[a-z]` range. If the hyphen is missing, or is at index `0`, validation immediately fails in $O(1)$ or $O(N)$ time before invoking heavier character-set checks.
2.  **Character Set Validation (`PCENChar`):** 
    Blink iterates through the remaining characters (handling both 8-bit `LChar` and 16-bit `UChar` buffers). Aside from the hyphen, it strictly rejects uppercase ASCII `[A-Z]` and restricts non-ASCII characters to defined Unicode ranges.
3.  **The "Hyphenated-Builtin" Blocklist:** 
    Containing a hyphen is a *necessary* condition, not a *sufficient* one. Blink cross-references the hyphenated string against a hardcoded blocklist of legacy SVG/MathML elements that predate the Custom Elements specification. If the name matches any of the following, validation fails despite the presence of a hyphen:
    *   `annotation-xml`
    *   `color-profile`
    *   `font-face`
    *   `font-face-src`
    *   `font-face-uri`
    *   `font-face-format`
    *   `font-face-name`
    *   `missing-glyph`

### 4. Failure Modes & Exception Handling
If a developer attempts to register a tag name that violates the hyphen requirement (e.g., `customElements.define('myelement', ...)` or `customElements.define('-my-element', ...)`):

*   **Execution Halts:** The registration process is aborted prior to constructor validation or prototype inspection.
*   **Exception Thrown:** Blink utilizes the `ExceptionState` object to throw a `DOMException` of type **`SyntaxError`** (`DOMExceptionCode::kSyntaxError`).
*   **Error Message:** `"Failed to execute 'define' on 'CustomElementRegistry': '" + name + "' is not a valid custom element name."`

### 5. Audit Matrix (Edge Cases)

| Input String | Hyphen Present? | Blink Validation Result | Audit Notes |
| :--- | :--- | :--- | :--- |
| `x-foo` | Yes (Index 1) | **PASS** | Standard valid baseline. |
| `x-` | Yes (Index 1) | **PASS** | Trailing hyphen is spec-compliant. |
| `a---b` | Yes (Indices 1-3)| **PASS** | Consecutive hyphens are spec-compliant. |
| `div` | No | **FAIL (`SyntaxError`)** | Missing hyphen. |
| `-x-foo` | Yes (Index 0) | **FAIL (`SyntaxError`)** | Violates `[a-z]` leading character rule. |
| `font-face` | Yes (Index 4) | **FAIL (`SyntaxError`)** | Caught by legacy SVG blocklist. |
| `x–foo` | No (U+2013) | **FAIL (`SyntaxError`)** | Uses En-Dash instead of U+002D Hyphen-Minus. |

**AUDIT CONCLUSION:** Blink's implementation of the hyphen validation requirement in `CustomElement::IsValidName` is strictly compliant with the WHATWG HTML Living Standard. No parser-bypass vulnerabilities identified. **— END LOG.**