**AUDIT LOG: AGENT 430**
**TARGET:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/css/`)
**SUBJECT:** CSS Nesting & Selector Tree Substitution (Expansion Mechanics)

---

### 1. Architectural Overview: In-Place AST Linking vs. Desugaring
Contrary to early spec conceptualizations that framed CSS Nesting as a pre-processor-like string concatenation or AST cloning phase ("desugaring"), Blink implements nesting **natively within the `CSSSelector` structure**. 

When Blink’s `CSSSelectorParser` encounters a nested style rule, it does not flatten the selector lists into a Cartesian product of complex selectors. Doing so would cause an exponential memory explosion (e.g., `.a, .b, .c { & .d, & .e { ... } }`). Instead, Blink links the child rule directly to the parent `StyleRule` in memory and resolves them dynamically during selector matching (`SelectorChecker`).

---

### 2. Core Data Structures
Blink represents selectors as a flattened array of `CSSSelector` objects (allocated in oilpan/heap memory via `CSSSelectorList`). 

To support tree substitution, `CSSSelector` utilizes specific `MatchType` and `PseudoType` enums:
*   **`CSSSelector::kPseudoParent` (`&`)**: Represents the explicit nesting selector.
*   **`CSSSelector::kPseudoIs` (`:is()`)**: The implicit wrapper mechanism.
*   **`DataUnion::parent_rule_`**: Instead of holding a string or an argument list, a `kPseudoParent` selector holds a `Member<const StyleRule> parent_rule_` pointer inside its `RareData` union.

---

### 3. The Substitution Pipeline (Parsing Phase)

When `CSSParserImpl::ConsumeStyleRule` processes a block, it pushes the current `StyleRule` onto a stack, passing it down as the `parent_rule_for_nesting` context to child rules.

#### A. Explicit Substitution (`&`)
1. The child selector contains an explicit `&` (e.g., `&.active` or `.foo &`).
2. `CSSSelectorParser` consumes the `&` token and generates a `CSSSelector` with `MatchType::kPseudoClass` and `PseudoType::kPseudoParent`.
3. Blink attaches the `parent_rule_for_nesting` pointer to this selector's `RareData`.
4. **No AST cloning occurs.** The `&` acts as a symlink to the parent `StyleRule`'s `CSSSelectorList`.

#### B. Implicit Substitution (Relative Selectors)
1. The child selector omits the `&` (e.g., `> .child` or `.descendant`).
2. Per the CSS Nesting specification, this is relative to the parent.
3. `CSSSelectorParser` **synthesizes** a leading `kPseudoParent` (`&`) selector and prepends it to the complex selector chain, separated by a descendant combinator (or the explicit combinator provided, like `>`).
4. *Memory layout for `.parent { > .child }`*:
   `[.child] --(kChild)--> [& (points to .parent)]` (Note: Blink stores selectors right-to-left for matching efficiency).

#### C. The `:is()` Equivalence
According to the W3C specification, the nesting selector `&` represents the elements matched by the parent rule's selector list, wrapped in an implicit `:is()`. 
In Blink, `kPseudoParent` is functionally an alias for `kPseudoIs`, with the crucial difference that `kPseudoIs` reads from a `CSSSelectorList*` owned by the pseudo-class itself, whereas `kPseudoParent` reads the `CSSSelectorList` directly from the `StyleRule*` it points to.

---

### 4. Specificity & Pseudo-Element Edge Cases

During the substitution audit, two critical constraints in Blink's implementation must be highlighted:

1.  **Specificity Calculation (`CSSSelector::Specificity()`):**
    Because `&` acts as `:is()`, it takes the **maximum specificity** of the complex selectors in the parent's selector list. When Blink calculates the specificity of a child rule, encountering `kPseudoParent` triggers a recursive call to `parent_rule_->SelectorList().MaximumSpecificity()`.
    *   *Anomaly*: `.a, #b { & .c {} }` -> The specificity of `&` is always `(1, 0, 0)` (from `#b`), even if the element only matches `.a`.

2.  **Pseudo-Element Rejection:**
    Just like `:is()`, the `&` selector cannot represent pseudo-elements. 
    If a parent rule is `.foo::before`, and a child rule is `& .bar`, Blink still parses it and points `&` to the parent rule. However, during matching, sub-selectors of a `kPseudoParent` that terminate in a pseudo-element automatically fail to match.

---

### 5. Runtime Expansion (`SelectorChecker`)

When Blink computes styles for a DOM element, `SelectorChecker::MatchSelector` walks the `CSSSelector` chain (from right to left).

When the checker hits `kPseudoParent`:
1.  It invokes `SelectorChecker::MatchPseudoParent`.
2.  It extracts the `StyleRule*` from `selector.ParentRule()`.
3.  It fetches the first selector from the parent rule's `CSSSelectorList`.
4.  It delegates the check to `MatchSelectorList` (the exact same engine used for `:is()` and `:where()`).
5.  **Recursion:** If the parent rule *also* is a nested rule, its selector list will contain its own `kPseudoParent`, causing `SelectorChecker` to recursively traverse up the `StyleRule` pointer tree until it hits the root rule.

### 6. CSSOM Serialization (The "Virtual" Expansion)
If JavaScript accesses `cssRule.selectorText` on a nested rule, Blink does not reconstruct the flattened selector. It serializes `kPseudoParent` back into the literal string `"&"` (unless it was an implicitly inserted `&` at the start of a relative selector, which is omitted during serialization to remain faithful to the authored stylesheet, or serialized per the latest CSSOM spec updates).

---

### 7. Summary of Audit Findings
*   **Memory Efficiency:** **OPTIMAL.** By utilizing `StyleRule` pointers inside `kPseudoParent` instead of AST duplication, Blink avoids combinatorial explosion in deeply nested sheets.
*   **Matching Overhead:** **MODERATE.** Deeply nested rules incur recursive `MatchSelectorList` calls at runtime, equivalent to deeply nested `:is()` functions. 
*   **Mutation Handling:** Because `kPseudoParent` points to the `StyleRule` itself (and not a copied selector list), mutating a parent rule's `selectorText` via CSSOM automatically and instantaneously updates the matching behavior of all nested child rules without requiring reparsing of the children.

**END OF REPORT - AGENT 430**