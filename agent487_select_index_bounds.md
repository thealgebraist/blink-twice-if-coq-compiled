**AUDIT REPORT: Blink `HTMLSelectElement::selectedIndex` Bounds Handling**
**Agent:** 487
**Target:** `third_party/blink/renderer/core/html/forms/html_select_element.cc`
**Specification:** WHATWG HTML Standard (4.10.7 The `select` element)

---

### 1. Executive Summary
Contrary to standard numeric clamping (where `val = std::clamp(val, min, max)`), the Blink implementation of `HTMLSelectElement::selectedIndex` **does not clamp** out-of-bounds indices to the nearest valid `HTMLOptionElement` index. Instead, out-of-bounds indices result in complete deselection of all options, resolving the effective `selectedIndex` to `-1` (or defaulting back to the first valid option depending on the `multiple` attribute and display `size`, primarily during layout/reset phases, though the explicit DOM setter forces `-1`).

Below is the detailed audit of how Blink handles index bounds, type conversions, and state resolution for `selectedIndex`.

---

### 2. WebIDL Type Conversion (Pre-Blink Boundary)
Before the value reaches `HTMLSelectElement::setSelectedIndex(int index)`, it passes through V8 and Blink's WebIDL bindings (`html_select_element.idl`).

* **IDL Definition:** `attribute long selectedIndex;`
* **Conversion Mechanic:** The ECMAScript value is converted to a 32-bit signed integer (`int32_t`) using the WebIDL `[EnforceRange]`-less modulo arithmetic (`ToInt32`).
* **Edge Cases:**
  * `NaN`, `+0`, `-0`, `+Infinity`, `-Infinity` $\rightarrow$ `0`.
  * `2147483648` ($2^{31}$) wraps to `-2147483648` due to 32-bit signed integer overflow.
  * Float values (e.g., `2.9`) are truncated towards zero (`2`).

---

### 3. Setter Audit: `HTMLSelectElement::setSelectedIndex(int index)`

When `select.selectedIndex = index` is invoked, Blink executes `SelectOption(index, 0)`.

```cpp
void HTMLSelectElement::setSelectedIndex(int index) {
  SelectOption(index, kDeselectOtherOptions);
}
```

#### Bounds Resolution Logic in `SelectOption`
1. **Option Lookup:** Blink attempts to map the passed `index` to a pointer via `OptionAtListIndex(int list_index)` (or by iterating `GetOptionList()`).
2. **Underflow (`index < 0`):** 
   * If `index` is `-1` (the standard value for "no selection") or any negative integer (e.g., `-999`), the lookup immediately fails and returns `nullptr`.
   * **Action:** No clamp to `0` occurs. All currently selected options have their `selectedness` set to `false`.
3. **Overflow (`index >= options.length`):**
   * The `HTMLOptionsCollection` bounds are exceeded. The lookup returns `nullptr`.
   * **Action:** No clamp to `options.length - 1` occurs. All currently selected options have their `selectedness` set to `false`.
4. **In-Bounds (`0 <= index < options.length`):**
   * The target `HTMLOptionElement` is retrieved.
   * All other options are deselected (`kDeselectOtherOptions` flag).
   * The target option's `SetSelectedState(true)` is called.

*Note on Disabled/Hidden Options:* Programmatic setting via `selectedIndex` bypasses `disabled` state checks. If index `2` is disabled, `select.selectedIndex = 2` will still successfully select it.

---

### 4. Getter Audit: `HTMLSelectElement::selectedIndex()`

When reading `select.selectedIndex`, Blink does not return the cached value passed to the setter; it dynamically calculates the index or pulls from the active selection state.

```cpp
int HTMLSelectElement::selectedIndex() const {
  // Iterates through the option list to find the first selected option.
  for (const auto& option : GetOptionList()) {
    if (option->Selected())
      return option-> index();
  }
  return -1;
}
```

#### Resulting Bounds Behavior
Because out-of-bounds values passed to the setter result in `option == nullptr` and trigger the deselection of all existing options, a subsequent read of `selectedIndex()` will fail to find any option where `option->Selected() == true`. 

Consequently, **all out-of-bounds inputs effectively clamp/resolve to `-1` upon retrieval.**

| Action / Input (`options.length == 3`) | Internal Target Option | Resulting `selectedIndex` Read |
| :--- | :--- | :--- |
| `select.selectedIndex = 1` | `options[1]` | `1` |
| `select.selectedIndex = -1` | `nullptr` | `-1` |
| `select.selectedIndex = -500` | `nullptr` | `-1` |
| `select.selectedIndex = 3` | `nullptr` | `-1` |
| `select.selectedIndex = 99999` | `nullptr` | `-1` |
| `select.selectedIndex = NaN` | `options[0]` (via WebIDL `ToInt32`) | `0` |

---

### 5. Implicit "Clamping" via `ResetToDefaultSelection()`
There is one scenario where Blink overrides an out-of-bounds `-1` state and forces an in-bounds selection (which behaves like a lower-bound clamp to `0`). This is governed by the HTML specification's **selectedness setting algorithm**.

If the `HTMLSelectElement` is in "single-selection" mode (`!multiple && display_size <= 1`):
1. **Initial Parse / Reset / DOM Mutation:** When options are added/removed, or the form is reset, `ResetToDefaultSelection()` is triggered.
2. If no option is explicitly marked `selected`, Blink will automatically select the **first non-disabled option** (effectively clamping the uninitialized `-1` state to `0`, or the lowest valid index).
3. **Exception:** When `selectedIndex` is set *programmatically* via JS to an out-of-bounds value (e.g., `select.selectedIndex = 50`), Blink explicitly allows the `select` element to remain in the `-1` (unselected) state, violating the visual expectation of a standard dropdown, until the next relevant DOM mutation occurs.

### 6. Audit Conclusion
The `HTMLSelectElement::selectedIndex` implementation in Blink strictly adheres to the WHATWG specification. It avoids mathematical clamping (`min`/`max`) in favor of **pointer-resolution fallback**: any index that does not map to a valid `0 <= i < length` memory address in the `OptionList` clears the selection register, normalizing all out-of-bounds states to `-1`.