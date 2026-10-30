In Chromium’s Blink rendering engine (specifically within the LayoutNG architecture), the **W3C CSS 2.1 Section 8.3.1 (Collapsing Margins)** specification is implemented using an explicit state machine driven by a lightweight data structure: `MarginStrut` (`third_party/blink/renderer/core/layout/margin_strut.h` and `.cc`).

Instead of looking backward and forward in the DOM tree to resolve margins simultaneously, LayoutNG transforms margin collapsing into a single-pass, forward-propagating accumulation problem using `MarginStrut`.

Here is a detailed architectural comparison between the W3C CSS 2.1 specification and Blink’s `MarginStrut` implementation across all major edge cases.

---

### 1. Core Data Structure vs. Spec Definitions

**W3C CSS 2.1 Section 8.3.1:**
Defines margin collapsing declaratively: adjoining vertical margins of two or more boxes combine to form a single margin.

**Blink `MarginStrut`:**
Models an "ongoing" collapse operation as a pipeline state passed down and across the layout tree (via `ConstraintSpace` onto `LayoutResult`).

```cpp
// Conceptual representation of blink::MarginStrut
struct MarginStrut {
  LayoutUnit positive_margin;
  LayoutUnit negative_margin;
  LayoutUnit quirky_positive_margin;
  bool is_quirky_container_start = false;

  void Append(LayoutUnit value, bool is_quirky);
  LayoutUnit Sum() const;
  bool IsEmpty() const;
};
```
*Note: All fields are initialized to `LayoutUnit()` (0).*

---

### 2. Positive, Negative, and Mixed Margins

#### **W3C Spec:**
1. **All Positive:** The collapsed margin is the maximum of the adjoining margins.
2. **All Negative:** The collapsed margin is the minimum (most negative) of the adjoining margins.
3. **Mixed (Positive & Negative):** The collapsed margin is the sum of the maximum positive margin and the minimum negative margin (i.e., `Max(Pos) + Min(Neg)`).

#### **Blink `MarginStrut` Implementation:**
Blink handles all three cases simultaneously without branching by splitting the state into `positive_margin` and `negative_margin` and resolving them lazily via `Sum()`.

* **Accumulation (`MarginStrut::Append`):**
  ```cpp
  void MarginStrut::Append(LayoutUnit value, bool is_quirky) {
    if (is_quirky_container_start && is_quirky)
      return; // Ignored due to quirks mode rules

    if (value < 0) {
      negative_margin = std::min(value, negative_margin);
    } else {
      if (is_quirky) {
        quirky_positive_margin = std::max(value, quirky_positive_margin);
      } else {
        positive_margin = std::max(value, positive_margin);
      }
    }
  }
  ```
* **Resolution (`MarginStrut::Sum`):**
  ```cpp
  LayoutUnit MarginStrut::Sum() const {
    return std::max(positive_margin, quirky_positive_margin) + negative_margin;
  }
  ```

#### **Edge Case Comparison:**
* **Zero Margins:** A `0px` margin hits the `else` branch: `std::max(0, 0)` remains `0`. `IsEmpty()` checks if all three LayoutUnits are `0`.
* **Subpixel Layout (LayoutUnit):** CSS 2.1 does not define subpixel arithmetic. Blink uses `LayoutUnit` (fixed-point math with 1/64th pixel precision). `MarginStrut` preserves subpixel precision during `std::max` and `std::min` operations, preventing rounding errors from compounding before `Sum()` is called.
* **Clamping:** If two massive negative margins collapse, `std::min` prevents integer underflow that would happen if they were summed, strictly adhering to CSS 2.1's "most negative" rule.

---

### 3. Quirks Mode

#### **W3C Spec:**
CSS 2.1 does not formally specify Quirks Mode; it is defined in the **WHATWG Quirks Mode Standard**. Specifically, in quirks mode, the top margin of a first-child element and the bottom margin of a last-child element are collapsed to `0` if they are inside a `<td>`, `<th>`, or `<body>` element.

#### **Blink `MarginStrut` Implementation:**
This is why `MarginStrut` has `quirky_positive_margin` and `is_quirky_container_start`.

1. **Top Margin Quirk (`is_quirky_container_start`):**
   When `BlockLayoutAlgorithm` begins laying out a `<body>` or `<td>` in Quirks Mode, it sets `margin_strut.is_quirky_container_start = true` on the initial strut. When a child element has a margin originating from a quirky HTML tag (like `<p>` or `<h1>` with default UA margins), `is_quirky` is passed as `true` to `Append()`. As seen in the code above, `Append()` immediately drops this margin (`return;`).
2. **Bottom Margin Quirk (`quirky_positive_margin`):**
   As elements are laid out, quirky positive margins are stored separately in `quirky_positive_margin`. If the strut reaches the bottom of a quirky container (`<td>`/`<body>`) without being resolved by a non-quirky element, the layout algorithm simply ignores `quirky_positive_margin` by calling `positive_margin + negative_margin` instead of `Sum()`, effectively zeroing out the trailing quirky margin.
3. **Edge Case - Negative Quirky Margins:**
   Notice in `Append()` that `if (value < 0)` does *not* check `is_quirky` (unless `is_quirky_container_start` is true). In legacy browser engines, negative margins were rarely produced by default UA stylesheets, so the bottom-margin quirk only separates *positive* quirky margins.

---

### 4. Self-Collapsing Margins

#### **W3C Spec:**
A box's own top and bottom margins collapse if the box has:
* `min-height: 0` (or computes to 0)
* `height: 0` or `auto`
* No top or bottom border
* No top or bottom padding
* No line boxes, and all of its in-flow children's margins (if any) also self-collapse.

#### **Blink `MarginStrut` Implementation:**
`MarginStrut` makes self-collapsing trivial. `MarginStrut` itself does not know if a box is self-collapsing; `BlockLayoutAlgorithm` orchestrates this.

1. **Incoming vs. Outgoing Strut:**
   A box receives an incoming `MarginStrut` from its previous sibling (or parent) via its `ConstraintSpace`.
2. **Appending Top Margin:**
   The box appends its own `margin-top` to this incoming strut.
3. **Through-Pass:**
   If the box has no border/padding and contains no inflow content (it is self-collapsing), the `MarginStrut` is never resolved (i.e., `Sum()` is not called to advance the BFC block-offset).
4. **Appending Bottom Margin:**
   The box simply appends its `margin-bottom` to the *exact same* `MarginStrut` instance and passes it out via its `LayoutResult` (`end_margin_strut`).

#### **Edge Case Comparison:**
* **Positioning a Self-Collapsing Box (CSS 2.1 § 8.3.1 Bullet 6):**
  The spec states that the top border edge of a self-collapsing box is defined by resolving its top margin with the preceding margins, *without* its bottom margin, unless its children affect it.
  In Blink, before the self-collapsing box appends its `margin-bottom` to the strut, the algorithm peeks at `margin_strut.Sum()` to record the box's `BfcOffset` (Block Formatting Context offset). Then, it appends `margin-bottom` and hands the mutated strut to the next sibling. Thus, the box's physical position and the final collapsed margin size are decoupled cleanly.

---

### 5. Parent-Child Margin Collapsing

#### **W3C Spec:**
* **Top:** The top margin of an in-flow block element collapses with its first in-flow block-level child's top margin if the element has no top border, no top padding, and the child has no clearance.
* **Bottom:** The bottom margin of an in-flow block-level element with a `height` of `auto` collapses with its last in-flow block-level child's bottom margin if the element has no bottom padding, no bottom border, and the child's bottom margin does not collapse with a top margin that has clearance.

#### **Blink `MarginStrut` Implementation:**
Blink handles this by controlling whether a `MarginStrut` is allowed to cross box boundaries.

* **Top Boundary:**
  * *Can Collapse:* The parent appends its `margin-top` to the `MarginStrut` and passes this strut down into the first child's `ConstraintSpace`. The parent's BFC block-offset remains unresolved ("adjoining").
  * *Cannot Collapse (e.g., `padding-top: 1px` or `overflow: hidden` creating a BFC):* The parent calls `margin_strut.Sum()`, advances the BFC block-offset by that amount, and passes a brand new, empty `MarginStrut()` to its first child.
* **Bottom Boundary:**
  * *Can Collapse:* The last child finishes layout and returns an `end_margin_strut` in its `LayoutResult`. The parent extracts this strut, calls `end_margin_strut.Append(parent_margin_bottom)`, and returns this combined strut as its own `end_margin_strut` to *its* parent/next-sibling.
  * *Cannot Collapse (e.g., `height: 100px` or `border-bottom: 1px solid`):* The parent takes the child's `end_margin_strut`, calls `.Sum()` to add it to the parent's intrinsic block size (if `height: auto`), and then creates a *new* `MarginStrut`, appends its own `margin-bottom` to it, and passes that out as its `end_margin_strut`.

---

### 6. Clearance (`clear: left | right | both`)

#### **W3C Spec:**
Clearance is the most complex aspect of CSS 2.1 Section 8.3.1 and Section 9.5.2.
* When an element has clearance, its top margin **cannot** collapse with its parent's bottom margin.
* If an element's top margin collapses with its parent's top margin, and the element has clearance, the margins still collapse *together*, wait until clearance is calculated, and prevent the parent's top margin from collapsing with preceding siblings' margins in the normal way (introducing the concept of negative clearance or shifting the parent).
* Clearance is introduced *above* the `margin-top` of the clearing element, effectively resetting the margin collapsing chain after the float is cleared.

#### **Blink `MarginStrut` Implementation:**
Clearance acts as a hard barrier to the `MarginStrut` pipeline in `BlockLayoutAlgorithm`.

1. **Detecting Clearance:**
   Before laying out a child, Blink checks if the child's `clear` property interacts with the current `ExclusionSpace` (where floats are tracked).
2. **Resolving the Strut:**
   If the child requires clearance (i.e., the BFC block-offset + `margin_strut.Sum()` is higher up than the bottom edge of the relevant float):
   * The `MarginStrut` is **consumed and reset**.
   * The algorithm calculates the exact BFC offset required to clear the float.
   * Because the `MarginStrut` is reset to empty (`MarginStrut()`), it cannot propagate out of the bottom of the parent anymore. This automatically satisfies the W3C rule: *"A box with clearance cannot collapse its top margin with its parent's bottom margin."*
3. **Edge Case: Self-Collapsing Box with Clearance:**
   If a box has `clear: both` and is self-collapsing (`height: 0`), its `margin-top` and `margin-bottom` still collapse with *each other*.
   In Blink, the box absorbs the incoming `MarginStrut`, appends its `margin-top`, appends its `margin-bottom`, resolves the clearance against the floats, and then **flushes** the strut so that subsequent siblings start with a fresh `MarginStrut` positioned at the float's bottom edge (or the resolved margin edge, whichever is greater).

---

### Summary Table: W3C CSS 2.1 vs. Blink `MarginStrut`

| Feature / Edge Case | W3C CSS 2.1 Section 8.3.1 | Blink `MarginStrut` + `BlockLayoutAlgorithm` |
| :--- | :--- | :--- |
| **Resolution Model** | Declarative set of "adjoining" relationships. | Imperative accumulator passed via `ConstraintSpace` & `LayoutResult`. |
| **Mixed Sign Margins** | $\max(\text{pos}) + \min(\text{neg})$ | `std::max(pos, quirky_pos) + neg` in `MarginStrut::Sum