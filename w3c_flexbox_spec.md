This is an architectural and algorithmic comparison between the **W3C CSS Flexible Box Layout Module Level 1 (Section 9.7: Resolving Flexible Lengths)** and its modern implementation in Chromium’s Blink rendering engine (**LayoutNG**). 

---

### Architectural Context: LayoutNG Refactoring

In older versions of Blink (Legacy Layout), flex resolution was handled directly inside `LayoutFlexibleBox::ResolveFlexibleLengths`. With the migration to **LayoutNG**, Blink decoupled the layout orchestration from the core math of the CSS Flexbox specification.

While `blink::FlexLayoutAlgorithm` (located in `third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc`) orchestrates the layout pass, the actual execution of W3C Section 9.7 is delegated to the `blink::FlexLine` and `blink::FlexItem` helper classes (located in `flexible_box_algorithm.cc`). 

Specifically, **`FlexLine::ResolveFlexibleLengths()`** is the direct implementation of Section 9.7.

---

### High-Level Mapping: W3C 9.7 vs. Blink

| W3C Spec Step (Section 9.7) | Blink Method / Implementation (`flexible_box_algorithm.cc`) |
| :--- | :--- |
| **Step 1**: Determine the used flex factor. | `FlexLine::ComputeMainSizeFromAspectRatioUsing()` & setup phase in `FlexLayoutAlgorithm::PlaceFlexItems()`. Sets `sign` (`kPositiveFlexibility` vs `kNegativeFlexibility`). |
| **Step 2**: Size inflexible items. | `FlexLine::FreezeInflexibleItems()` |
| **Step 3**: Calculate initial free space. | Handled inside `FlexLine::FreezeInflexibleItems()` via `remaining_free_space_`. |
| **Step 4**: Loop (a through e). | `while (!ResolveFlexibleLengths()) { ... }` loop inside `FlexLayoutAlgorithm`. |
| **Step 4.a**: Check for flexible items. | `if (unfrozen_items.IsEmpty()) return true;` |
| **Step 4.b**: Calculate remaining free space & sum of flex factors. | `total_flex_grow_`, `total_flex_shrink_`, `total_weighted_flex_shrink_` & `initial_free_space_` adjustments. |
| **Step 4.c**: Distribute free space. | Conditional math inside `FlexLine::ResolveFlexibleLengths()`. |
| **Step 4.d**: Fix min/max violations. | `FlexItem::ClampSizeToMinAndMax()` and `total_violation` accumulation. |
| **Step 4.e**: Freeze over-constrained items. | `FlexLine::FreezeViolations()` |
| **Step 5**: Set main size. | Final assignment to `FlexItem::flexed_content_size_` and `LayoutUnit` rounding distribution. |

---

### Deep Dive: The 5-Step Freeze Loop & Core Mechanics

#### 1. Initial Setup and Freezing Inflexible Items (Steps 1–3)
**The W3C Spec:**
Determines whether to use `flex-grow` or `flex-shrink` based on whether the sum of outer hypothetical main sizes is less than or greater than the container’s inner main size. It then immediately freezes items that have a flex factor of `0`, or where the hypothetical main size violates the base size in the direction of flexing.

**Blink Implementation (`FlexLine::FreezeInflexibleItems`):**
Blink pre-calculates `sum_hypothetical_main_size_` as items are added to the `FlexLine`. 
```cpp
// Conceptual representation of Blink's setup
FlexSign flex_sign = (sum_hypothetical_main_size_ < container_main_inner_size_) 
                     ? kPositiveFlexibility 
                     : kNegativeFlexibility;
```
Blink iterates over `line_items_`. An item is frozen immediately (its `frozen_` boolean flag is set to `true`) if:
* `flex_grow == 0` (when `kPositiveFlexibility`) or `flex_shrink == 0` (when `kNegativeFlexibility`).
* `flex_Sign == kPositiveFlexibility` and `flex_base_content_size_ > hypothetical_main_content_size_`.
* `flex_Sign == kNegativeFlexibility` and `flex_base_content_size_ < hypothetical_main_content_size_`.

When an item is frozen in this step, its target size (`flexed_content_size_`) is set to its `hypothetical_main_content_size_`, and Blink subtracts this item's outer size from `remaining_free_space_`. Once this completes, Blink snapshots `initial_free_space_ = remaining_free_space_`.

#### 2. The Resolution Loop & Remaining Free Space (Step 4.a - 4.b)
**The W3C Spec:**
Requires a loop because clamping an item to its `min` or `max` size changes the amount of free space available to the remaining items, requiring a recalculation for unfrozen items. 
Crucially, Step 4.b states: *If the sum of the unfrozen flex items’ flex factors is less than one, multiply the initial free space by this sum.*

**Blink Implementation:**
Instead of recalculating `total_flex_grow_`, `total_flex_shrink_`, and `total_weighted_flex_shrink_` from scratch on every iteration of the loop (which would be $O(N^2)$), Blink maintains these as **running totals** on the `FlexLine` object. Whenever an item is frozen, its specific flex factors are subtracted from the running totals.

To handle the fractional flex factor rule (Step 4.b):
```cpp
double sum_flex_factors = (flex_sign == kPositiveFlexibility) 
                          ? total_flex_grow_ 
                          : total_flex_shrink_;

if (sum_flex_factors > 0 && sum_flex_factors < 1) {
  LayoutUnit fractional(initial_free_space_ * sum_flex_factors);
  if (fractional.Abs() < remaining_free_space_.Abs()) {
    remaining_free_space_ = fractional;
  }
}
```
*Note: Blink uses `double` for flex factors to prevent precision loss when summing fractional CSS values (like `0.333333`), while sizes use `LayoutUnit` (a 26.6 fixed-point integer).*

#### 3. Flex Grow and Flex Shrink Distribution (Step 4.c)
**The W3C Spec:**
* **Grow:** $\text{item main size} = \text{flex base size} + \left(\text{remaining free space} \times \frac{\text{flex grow factor}}{\sum \text{flex grow factors}}\right)$
* **Shrink:** Uses a **scaled flex shrink factor** (multiplying the item's `flex-shrink` factor by its inner flex base size) so that larger items shrink noticeably more than smaller items before hitting zero.

**Blink Implementation:**
Inside `FlexLine::ResolveFlexibleLengths()`, Blink loops through unfrozen items and distributes space:

```cpp
if (remaining_free_space_ != 0) {
  for (FlexItem& item : line_items_) {
    if (item.frozen_) continue;
    
    double extra_space = 0;
    if ( remaining_free_space_ > 0 && total_flex_grow_ > 0 && flex_sign == kPositiveFlexibility) {
      extra_space = remaining_free_space_ * item.flex_grow_ / total_flex_grow_;
    } else if (remaining_free_space_ < 0 && total_weighted_flex_shrink_ > 0 && flex_sign == kNegativeFlexibility) {
      extra_space = remaining_free_space_ * item.flex_shrink_ * item.flex_base_content_size_ / total_weighted_flex_shrink_;
    }
    
    item.flexed_content_size_ = item.flex_base_content_size_ + LayoutUnit::FromDoubleRound(extra_space);
  }
}
```
Notice `total_weighted_flex_shrink_`. Blink pre-multiplies `item.flex_shrink_ * item.flex_base_content_size_` during the initialization phase and maintains it as a `double`.

#### 4. Min/Max Violation Detection and Resolution (Steps 4.d - 4.e)
This is the most complex part of the algorithm. If an item grows beyond `max-width` or shrinks below `min-width`, it is a "violation". 

**The W3C Spec:**
1. Clamp the item's target main size by its min and max main size (and floor the content-box size at zero).
2. Calculate the **total violation**: $\sum (\text{clamped size} - \text{unclamped size})$.
3. **Freeze**:
   * If total violation is **Zero**: Freeze **all** items. (Exit loop).
   * If total violation is **Positive**: Freeze only the items that had **min** violations (clamped size > unclamped size).
   * If total violation is **Negative**: Freeze only the items that had **max** violations (clamped size < unclamped size).

*Why does the spec do this?* If one item hits a `max-width` (negative violation, leaving *more* free space for others) and another item hits a `min-width` (positive violation, taking *away* free space from others), they counteract each other. The spec only freezes the dominant violation type and forces a recalculation, because resolving the dominant violation might naturally pull the other item out of its violation state on the next pass.

**Blink Implementation (`ClampSizeToMinAndMax` & `FreezeViolations`):**
Blink partitions the unfrozen items into temporary vectors based on their violation state during the loop:

```cpp
Vector<FlexItem*> min_violations;
Vector<FlexItem*> max_violations;
LayoutUnit total_violation;

for (FlexItem& item : line_items_) {
  if (item.frozen_) continue;

  LayoutUnit clamped_size = item.ClampSizeToMinAndMax(item.flexed_content_size_);
  LayoutUnit violation = clamped_size - item.flexed_content_size_;
  
  if (violation > 0) {
    min_violations.push_back(&item);
  } else if (violation < 0) {
    max_violations.push_back(&item);
  }
  total_violation += violation;
  item.flexed_content_size_ = clamped_size;
}
```

Then, Blink executes Step 4.e by calling `FreezeViolations()`:
```cpp
if (total_violation == 0) {
  FreezeAllItems();
} else if (total_violation > 0) {
  FreezeViolations(min_violations);
} else {
  FreezeViolations(max_violations);
}
```

Inside `FreezeViolations(vector)`, Blink performs the state updates that allow the next iteration of the `while` loop to run in $O(N)$ time without re-evaluating frozen items:
1. Sets `item->frozen_ = true`.
2. Subtracts the newly clamped `item->flexed_content_size_` (plus margins/borders/padding) from `remaining_free_space_`.
3. Subtracts `item->flex_grow_`, `item->flex_shrink_`, and the weighted shrink factor from the `FlexLine`'s running totals.
4. Returns `false` to `ResolveFlexibleLengths()`, signaling the outer `while` loop to run another pass for the remaining unfrozen items. If `total_violation == 0`, it returns `true`, breaking the loop.

---

### Key Divergences & Engine-Specific Realities

While Blink strictly follows the mathematical intent of W3C Section 9.7, implementing a specification in a real-world C++ engine introduces edge cases not explicitly detailed in the spec's pure math:

#### 1. Fixed-Point Arithmetic (`LayoutUnit`) and Subpixel Accumulation
The W3C spec assumes real numbers ($\mathbb{R}$). Blink uses `LayoutUnit`, which quantizes layout values into $\frac{1}{64}\text{th}$ of a pixel. 
* **The Problem:** When dividing `remaining_free_space_` among 3 items with `flex-grow: 1`, `LayoutUnit::FromDoubleRound(extra_space)` may lose $\frac{1}{64}\text{px}$ or gain $\frac{1}{64}\text{px}$ due to rounding. This can cause the final `remaining_free_space_` to not equal `0`, or cause a false-positive `total_violation` of `1` subpixel.
* **Blink's Solution:** After the main loop finishes, Blink runs a post-processing pass to distribute any leftover subpixel `remaining_free_space_` (leftover solely from rounding errors) across the flexible items so that `justify-content` doesn't accidentally trigger on a 0.015px gap.

#### 2. Floating-Point Underflow in Flex Factors
Web developers occasionally write CSS using massive or microscopic numbers (e.g., `flex-grow: 0.0000001` or `flex-shrink: 999999999`). 
* When calculating `total_weighted_flex_shrink_`, multiplying `double