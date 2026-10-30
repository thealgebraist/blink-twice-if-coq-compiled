**AUDIT LOG: AGENT 494**
**TARGET:** Chromium / Blink Rendering Engine (`FocusController`)
**SUBJECT:** `tabindex` Focus Navigation and Lexicographical Ordering Analysis

---

### 1. Executive Summary: The "Lexicographical" Misconception

In the context of auditing Blink’s focus navigation, the term "lexicographical ordering" requires immediate clarification. 

**Blink does NOT sort `tabindex` values alphabetically (as strings).** If it did, `tabindex="10"` would precede `tabindex="2"`. Instead, Blink parses `tabindex` attributes into 32-bit signed integers and applies a **strict mathematical (numerical) sort**, followed by a **lexicographical tie-breaker** based on DOM tree order (Pre-order Depth-First Traversal). 

Therefore, the focus order is defined by a composite key: **`(TabIndex_Value, DOM_Insertion_Order)`**.

---

### 2. The Blink Focus Priority Tiers

Within a single Focus Navigation Scope (e.g., the `Document`, a `ShadowRoot`, or a `<slot>`), Blink categorizes elements into distinct operational tiers based on their parsed integer values:

1. **Tier 0: Excluded (`tabindex < 0`)**
   * **Behavior:** Removed from the sequential focus navigation order (Tab ring).
   * **Exception:** Can still be focused programmatically via `.focus()` or mouse click.
2. **Tier 1: Positive Values (`tabindex > 0`)**
   * **Behavior:** Prioritized above all standard interactive elements.
   * **Sorting:** Ascending **numerical** order ($1, 2, 3 \dots 10 \dots 32767$).
   * **Tie-Breaking:** If two elements share the same positive integer, Blink resolves the collision using DOM tree order (Pre-order traversal).
3. **Tier 2: Neutral / Implicit (`tabindex="0"` or intrinsic focusability)**
   * **Behavior:** Visited only *after* all Tier 1 elements in the current scope are exhausted.
   * **Includes:** Explicit `tabindex="0"` and natively focusable elements (`<button>`, `<input>`, `<a href>`, etc.) without a `tabindex` attribute.
   * **Sorting:** Strictly follows DOM tree order.

---

### 3. Edge Cases & Parsing Mechanics in Blink

As part of this audit, we must account for how Blink’s HTML parser (`HTMLConstructionSite` and `Element::tabIndex()`) normalizes non-standard `tabindex` inputs before passing them to the `FocusController`.

* **String / Invalid Inputs (`tabindex="abc"`):** 
  * Fails integer parsing. Blink ignores the attribute entirely. If the element is natively focusable, it defaults to Tier 2 (`0`). If not, it is unfocusable.
* **Alphanumeric Prefixes (`tabindex="20px"`):**
  * Blink uses the HTML specification's "rules for parsing integers." Leading whitespace is skipped, the sign is read, and digits are parsed until a non-digit is hit. `tabindex="20px"` evaluates to `20`.
* **Leading Zeros (`tabindex="02"`):**
  * Parsed as the integer `2`. Holds the exact same priority as `tabindex="2"`.
* **32-Bit Integer Overflow:**
  * If a value exceeds `INT_MAX` ($2,147,483,647$), parsing fails or clamps depending on architecture, generally resulting in the attribute being ignored or treated as `0`.

---

### 4. Scoped Focus Navigation (Shadow DOM & Slots)

Blink does not flatten the entire document into a single array of `tabindex` values. Doing so would allow a web component with `tabindex="1"` to hijack focus from the host document. Instead, Blink uses **Focus Scopes** (`ScopedFocusNavigation`).

The ordering becomes lexicographical across scopes: **`(Scope_Order, TabIndex_Value, DOM_Order)`**.

1. Blink navigates the Root Scope (Tier 1, then Tier 2).
2. When Blink encounters a **Scope Owner** (e.g., a Shadow Host or an `<iframe/>`) during traversal, it pauses traversal of the parent scope and steps *into* the child scope.
3. Inside the Shadow Root, it runs a completely isolated `tabindex` sort (Tier 1, then Tier 2 *local to that Shadow Root*).
4. Once the child scope is exhausted, focus returns to the parent scope at the exact point it left off.

*Audit Note:* If a Shadow Host itself has `tabindex="1"`, the entire Shadow Tree's focusable contents are visited at the `tabindex="1"` position of the parent scope.

---

### 5. Audit Verification Matrix

Consider the following DOM structure injected into Blink:

```html
<button id="A" tabindex="10">A</button>
<button id="B" tabindex="2">B</button>
<button id="C" tabindex="0">C</button>
<button id="D">D</button>
<div id="host" tabindex="2">
  #shadow-root
    <button id="E" tabindex="5">E</button>
    <button id="F" tabindex="1">F</button>
</div>
<button id="G" tabindex="2">G</button>
<button id="H" tabindex="-1">H</button>
```

**Blink `FocusController` Execution Order:**

1. **`#B`** (`tabindex="2"`, first in DOM)
2. **`#host`** (`tabindex="2"`, second in DOM — *Note: If the host isn't focusable itself, it acts as a scope boundary here*)
3. **`#F`** (Inside `#host` scope, local `tabindex="1"`)
4. **`#E`** (Inside `#host` scope, local `tabindex="5"`)
5. **`#G`** (`tabindex="2"`, third in DOM)
6. **`#A`** (`tabindex="10"`, numerical sort places 10 after 2)
7. **`#C`** (`tabindex="0"`, Tier 2, first in DOM)
8. **`#D`** (Implicit `0`, Tier 2, second in DOM)
* *Skipped:* **`#H`** (Tier 0, excluded).

---

### 6. Conclusion

Blink's focus navigation is an implementation of a **Scoped, Numerically-Weighted Pre-Order Depth-First Traversal**. True lexicographical (dictionary) sorting is never applied to the `tabindex` string itself, preventing the common "10 before 2" sorting bug, while DOM tree position acts as the secondary sorting attribute for all ties. 

**Agent 494 — Audit Complete.**