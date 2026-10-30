**AGENT 481 — AUDIT LOG: BLINK INPUT SELECTION RANGE BOUNDS**
**Component:** `third_party/blink/renderer/core/html/forms/text_control_element.cc`
**Specification Reference:** HTML Living Standard § 4.10.5.2.8 (Text field selection APIs)

---

### 1. Executive Summary
This audit details the boundary enforcement and clamping mechanisms within the Chromium Blink rendering engine when setting selection ranges on `<input>` and `<textarea>` elements (inheriting from `HTMLTextFormControlElement`). The primary objective of this logic is to ensure that arbitrary DOM API inputs (`selectionStart`, `selectionEnd`, `setSelectionRange`) never exceed the underlying string buffer's physical length (`value.length()`) or result in an inverted range (`start > end`), preventing out-of-bounds memory reads in the layout and editing engines.

---

### 2. Core Implementation: `setSelectionRange`
The primary entry point for range manipulation is `HTMLTextFormControlElement::setSelectionRange`. The parameters passed from the V8 bindings for `start` and `end` are unsigned 32-bit integers (`unsigned`), inherently preventing negative index injection at the C++ layer (negative JS values wrap via WebIDL `unsigned long` conversion rules prior to reaching Blink).

#### Step-by-Step Clamping Logic:

1. **Length Resolution:**
   Blink retrieves the current length of the inner editor value. Note that this uses UTF-16 code units, matching JavaScript's `String.prototype.length`.
   ```cpp
   const unsigned length = Value().length();
   ```

2. **Upper-Bound Clamping (Value Length):**
   Both `start` and `end` offsets are independently clamped to the maximum length of the current value. If an offset exceeds the string length, it snaps to the end of the string.
   ```cpp
   end = std::min(end, length);
   start = std::min(start, length);
   ```

3. **Relational Clamping (Start vs. End):**
   Per the WHATWG specification, the `start` offset cannot exceed the `end` offset. Rather than throwing an `IndexSizeError` (as the legacy DOM Range API does), the Text Control API silently collapses the selection to the `end` position if `start > end`.
   ```cpp
   if (start > end)
     start = end;
   ```
   *Note: In Blink's actual implementation, steps 2 and 3 are frequently combined into the following sequence:*
   ```cpp
   end = std::min(end, Value().length());
   start = std::min(start, end);
   ```
   *Mathematically, `std::min(start, std::min(end, length))` guarantees both upper-bound and relational clamping simultaneously.*

---

### 3. Single-Attribute Setter Edge Cases
When scripts mutate `input.selectionStart` or `input.selectionEnd` individually, Blink must reconcile the mutated boundary against the existing boundary *before* passing the values to `setSelectionRange`.

#### A. Setting `selectionStart(unsigned start)`
If the new `start` value is greater than the *current* `selectionEnd`, Blink pulls the `end` marker forward to match the new `start` (collapsing the range at the new `start` position, subject to subsequent `length` clamping).
```cpp
void HTMLTextFormControlElement::setSelectionStart(unsigned start) {
  setSelectionRange(start, std::max(start, selectionEnd()), selectionDirection());
}
```
* **Audit Trace:** `Value().length() = 5`, current `end = 2`. User sets `selectionStart = 10`.
* `std::max(10, 2)` yields `10`.
* `setSelectionRange(10, 10)` is called.
* Clamping reduces both to `5`. Result: `[5, 5]`.

#### B. Setting `selectionEnd(unsigned end)`
If the new `end` value is less than the *current* `selectionStart`, it does not pre-clamp `start`. It passes the current `start` and the new `end` directly to `setSelectionRange`, which handles the inversion.
```cpp
void HTMLTextFormControlElement::setSelectionEnd(unsigned end) {
  setSelectionRange(selectionStart(), end, selectionDirection());
}
```
* **Audit Trace:** `Value().length() = 5`, current `start = 4`. User sets `selectionEnd = 2`.
* `setSelectionRange(4, 2)` is called.
* `end` clamps to `std::min(2, 5) -> 2`.
* `start` clamps to `std::min(4, 2) -> 2`. Result: `[2, 2]`.

---

### 4. Shadow DOM & `FrameSelection` Synchronization
Once `start` and `end` are clamped at the `HTMLTextFormControlElement` level, Blink translates these flat string indices into DOM positions within the inner `TextControlInnerEditorElement` (the user-agent Shadow DOM `<div>` holding the text node).

1. **Cache Update:** If the element is not focused or does not have an active layout object, the clamped values are written to `cached_selection_start_` and `cached_selection_end_`.
2. **Grapheme / Surrogate Pair Handling:** While the DOM API allows setting a selection index in the middle of a UTF-16 surrogate pair (e.g., splitting an emoji), when mapping to `VisibleSelection` in `FrameSelection`, Blink's `Position` iterator may adjust the visual caret to avoid rendering mid-character, though the getter for `selectionStart`/`End` will still return the exact clamped code-unit offset.
3. **Value Mutation Reset:** If `input.value` is programmatically overwritten via `setValue()`, Blink checks the validity of the existing selection cache. By default, setting a new value clamps or moves the selection to the end of the new `value.length()`, unless `SetValueSelection::kClamp` is explicitly specified during internal updates (which runs `std::min(cached_offset, new_length)`).

---

### 5. Audit Conclusion
**Status: SECURE / SPEC-COMPLIANT.**
Blink's implementation of selection clamping strictly adheres to the HTML standard. By utilizing `unsigned` types and executing `std::min` chains against `Value().length()` prior to instantiating `SelectionInDOMTree`, there is no vector for out-of-bounds offset propagation into the `core/editing` subsystem via the selection APIs.

**AGENT 481 — END OF REPORT**