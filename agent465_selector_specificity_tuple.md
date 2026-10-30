**Audit Report: Blink CSS Selector Specificity Calculation and Packing**
**Auditor:** Agent 465
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/css/css_selector.cc` & `css_selector.h`)

---

### 1. Overview of Specificity Tuple
According to the W3C Selectors Level 4 specification, a selector's specificity is calculated as a 3-tuple of components: `(a, b, c)`. 
*   **`a` (IDs):** Counts ID selectors (`#example`).
*   **`b` (Classes/Attributes):** Counts class selectors (`.example`), attributes (`[type="text"]`), and pseudo-classes (`:hover`).
*   **`c` (Tags/Elements):** Counts type selectors (`div`) and pseudo-elements (`::before`).

To optimize RuleSet cascade sorting and prevent tuple-comparison overhead during style resolution, Blink packs these three values into a single 32-bit unsigned integer (`uint32_t`).

---

### 2. Integer Packing Architecture
Blink allocates 8 bits per specificity component, utilizing the lower 24 bits of a 32-bit unsigned integer. The upper 8 bits remain unused by standard selector specificity (though sometimes leveraged for higher-level cascade context in adjacent systems).

**Bitwise Masks and Shifts:**
*   **`a` (ID) Component:**
    *   Shift: `16` bits (`kIdMask = 0xff0000`)
    *   Bits: `16–23`
*   **`b` (Class/Attr/Pseudo-class) Component:**
    *   Shift: `8` bits (`kClassMask = 0x00ff00`)
    *   Bits: `8–15`
*   **`c` (Tag/Pseudo-element) Component:**
    *   Shift: `0` bits (`kElementMask = 0x0000ff`)
    *   Bits: `0–7`

**Memory Layout (32-bit `uint32_t`):**
```text
[ 31 ... 24 ] [ 23 ... 16 ] [ 15 ... 8 ] [ 7 ... 0 ]
   Unused      Component A   Component B  Component C
  (0x00)         (IDs)        (Classes)     (Tags)
```

---

### 3. Overflow Mitigation (Saturating Addition)
A critical vulnerability in naive bit-packing is component overflow. If a selector contains 256 class selectors, standard addition would overflow the `b` component (`0x010000`), bleeding into the `a` component and falsely elevating the selector to the specificity of an ID.

Blink mitigates this by enforcing **saturating addition** at the byte boundary (`255` or `0xFF`).

**Implementation Logic (`CSSSelector::Specificity`):**
When Blink iterates through a complex selector list to sum specificities, it does not simply add the packed integers. It uses an internal helper (often `AddSpecificities(uint32_t a, uint32_t b)`) which isolates each mask, adds them, and clamps the result to the mask's maximum value before bitwise OR-ing them back together:

1.  **Extract and Add:** `result_a = (spec1 & kIdMask) + (spec2 & kIdMask)`
2.  **Clamp (Saturate):** If `result_a > kIdMask`, set `result_a = kIdMask` (`0xFF0000`).
3.  *(Repeat logic for `kClassMask` and `kElementMask`)*
4.  **Pack:** `return result_a | result_b | result_c`

Each component can therefore represent a maximum count of **255**. Any additional selectors of that type within the same compound chain are ignored for specificity purposes.

---

### 4. Ordering and Special Selectors
Because `a` occupies the most significant bits, `b` the middle, and `c` the least significant, Blink can evaluate the specificity of two rules using a single CPU instruction (`>` or `<`) on the packed `uint32_t`.

**Special Case Handling in `SpecificityForOneSelector()`:**
*   **Universal Selector (`*`) & Combinators (`>`, `+`, `~`):** Return `0x000000`.
*   **`:where()`:** Always returns `0x000000`, overriding the specificity of its arguments.
*   **`:is()`, `:not()`, `:has()`:** These pseudo-classes do not add to the `b` component themselves. Instead, Blink iterates through their internal `CSSSelectorList` argument and returns the **maximum** packed `uint32_t` value found among the sub-selectors.
*   **`::slotted()` and `:host()`:** Return `kClassMask` (`0x000100`) plus the specificity of their compound arguments (evaluated via saturating addition).

### 5. Audit Conclusion
Blink's `CSSSelector::Specificity()` implementation is compliant with CSSWG specifications. The 8-bit clamping boundary (`255`) is standard across major engines (matching WebKit and Gecko) and successfully prevents bit-bleed escalation attacks or rendering bugs caused by machine-generated, deeply nested CSS rules.