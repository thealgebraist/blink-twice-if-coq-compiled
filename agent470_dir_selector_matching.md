**AUDIT REPORT: Agent 470**  
**Target Subsystem:** Blink Rendering Engine (`third_party/blink/renderer/core/css/`)  
**Subject:** `:dir()` Pseudo-Class Selector Matching and Directionality Boolean Branching  

---

### 1. Executive Summary
The `:dir()` pseudo-class matches elements based on their *HTML-defined directionality*, which is strictly distinct from the CSS `direction` property (though the default UA stylesheet maps them). In Blink, resolving `:dir()` does not trigger a style recalc; instead, it relies on a cached, inherited DOM state (`TextDirection` enum) stored directly on `Node`/`Element` bitfields, resolving down to a tight boolean branch during selector checking.

### 2. Primary Audit Location: `SelectorChecker`
The core evaluation occurs in `blink::SelectorChecker::CheckPseudoClass`. When the `CSSSelector::kPseudoDir` enum is encountered, the engine executes the following logical branch:

```cpp
// Location: third_party/blink/renderer/core/css/selector_checker.cc

case CSSSelector::kPseudoDir: {
  const AtomicString& argument = selector.Argument();
  if (argument.IsNull()) {
    return false;
  }
  
  // Directionality is fetched from the DOM tree, not ComputedStyle.
  TextDirection direction = element.CachedDirectionality();
  
  if (EqualIgnoringASCIICase(argument, "ltr")) {
    return direction == TextDirection::kLtr;
  }
  if (EqualIgnoringASCIICase(argument, "rtl")) {
    return direction == TextDirection::kRtl;
  }
  return false;
}
```

#### Branching Breakdown:
1. **Null Guard:** If the parser failed to capture an argument (though usually caught at parse-time by `CSSSelectorParser`), it branches `false`.
2. **Argument Matching (ASCII Case-Insensitive):**
   * **Branch A (`"ltr"`):** Compares `direction == TextDirection::kLtr` (Underlying value: `1` or `0` depending on platform `TextDirection` enum definition, typically `kRtl = 0, kLtr = 1`).
   * **Branch B (`"rtl"`):** Compares `direction == TextDirection::kRtl`.
   * **Fallback Branch:** Any other argument (e.g., `:dir(auto)`, `:dir(invalid)`) fails the string comparison and returns `false`. Note: `:dir(auto)` is not a valid match state; elements with `dir="auto"` resolve to either `kLtr` or `kRtl` before matching.

---

### 3. State Resolution: `CachedDirectionality()`
To understand how the `TextDirection` boolean equivalent is derived prior to the `SelectorChecker` branch, we audit `blink::Element` and `blink::HTMLElement` (`third_party/blink/renderer/core/html/html_element.cc`).

Blink avoids O(N) ancestor traversal during CSS matching by maintaining two state flags in `NodeRareData` / `Element` bitfields:
* `has_dir_auto_` (Boolean)
* `cached_directionality_` (1-bit field representing `TextDirection::kLtr` vs `TextDirection::kRtl`)

#### The Directionality Resolution Branching Tree:
When DOM mutations or text changes occur, Blink calculates the cached bit via the following hierarchy:

1. **Explicit `dir="ltr"`:**  
   `cached_directionality_` $\rightarrow$ `TextDirection::kLtr`.
2. **Explicit `dir="rtl"`:**  
   `cached_directionality_` $\rightarrow$ `TextDirection::kRtl`.
3. **Explicit `dir="auto"` (or `<bdi>` without `dir`):**  
   * Sets `has_dir_auto_ = true`.
   * **Branch `<input>` / `<textarea>`:** Evaluates the `value` string.
   * **Branch Standard Element:** Traverses child text nodes (skipping `<script>`, `<style>`, `<bdi>`, and elements with explicit `dir`).
   * **Bidi Character Evaluation:** Scans UTF-16 code units using ICU (`u_charDirection`).
     * First strong character is `U_LEFT_TO_RIGHT` $\rightarrow$ `TextDirection::kLtr`.
     * First strong character is `U_RIGHT_TO_LEFT` or `U_RIGHT_TO_LEFT_ARABIC` $\rightarrow$ `TextDirection::kRtl`.
     * No strong characters found $\rightarrow$ **Fallback Branch:** Returns `TextDirection::kLtr` (per HTML spec).
4. **No `dir` Attribute (or invalid value):**
   * **Branch Shadow Host / Slotted Content:** Inherits `cached_directionality_` from the flat-tree parent (`ParentOrShadowHostElement()`).
   * **Branch Root `<html>` Element:** If no `dir` is present on the document element, defaults unconditionally to `TextDirection::kLtr`.

---

### 4. Invalidation & Pseudo-State Propagation
When an element's directionality bit flips (e.g., programmatic change to `element.dir` or text mutation inside a `dir="auto"` container), Blink executes `HTMLElement::UpdateDirectionalityAndDescendant()`:

```cpp
if (CachedDirectionality() != new_direction) {
  SetCachedDirectionality(new_direction);
  // Triggers CSS invalidation for :dir()
  PseudoStateChanged(CSSSelector::kPseudoDir);
  // Propagates bit-flip down the flat tree to inheriting children
  ...
}
```

### 5. Audit Findings & Edge-Case Verification
* **Shadow DOM Isolation:** Audited and verified. Directionality inheritance uses flat-tree traversal (`FlatTreeTraversal::ParentElement`). A `:dir(rtl)` inside a Shadow Tree correctly resolves to `true` if the Shadow Host is `rtl`.
* **Disconnected Elements:** Elements not connected to the Document tree still compute `CachedDirectionality()`. If disconnected and lacking an explicit `dir` attribute on their disconnected subtree root, the root defaults to `TextDirection::kLtr`.
* **Performance Characteristic:** Because `CachedDirectionality()` reads a pre-computed bitfield on the `Element`, `:dir()` matching in `SelectorChecker` is $O(1)$ and allocation-free.

**Audit Status:** COMPLETE. Directionality branching logic is sound and compliant with WHATWG HTML and W3C Selectors Level 4 specifications.