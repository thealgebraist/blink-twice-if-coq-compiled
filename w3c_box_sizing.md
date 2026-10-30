In Chromium’s Next-Generation Layout engine (LayoutNG), `third_party/blink/renderer/core/layout/ng/ng_length_utils.cc` (now largely migrated to `core/layout/length_utils.cc`) serves as the mathematical bridge between W3C CSS specifications and concrete pixel geometry. 

Here is an architectural comparison between Blink’s `InlineSizeFromAspectRatio` and `ComputeReplacedSize` implementations and the **CSS Box Model Level 3**, **CSS Sizing Level 3**, and **CSS Sizing Level 4** specifications.

---

### 1. Spec-to-Code Mapping Overview

| W3C Specification Concept | Blink Implementation (`length_utils.cc`) | Primary Role |
| :--- | :--- | :--- |
| **CSS Box Model 3**: `box-sizing`, border/padding (`NGBoxStrut`) | `BoxSizing::kContentBox`, `BoxSizing::kBorderBox`, `border_padding` | Determines whether dimensions and ratios include or exclude the `NGBoxStrut`. |
| **CSS Sizing 3**: Intrinsic Size Resolution (Replaced Elements) | `ComputeReplacedSize()` | Resolves `<img>`, `<video>`, `<canvas>` using the "Constraint Equation" (Intrinsic sizes vs. CSS min/max/preferred sizes). |
| **CSS Sizing 4**: `aspect-ratio` property | `InlineSizeFromAspectRatio()`, `BlockSizeFromAspectRatio()` | Translates a single definite dimension into the opposite dimension using a `LogicalAspectRatio`. |

*Note on Blink Architecture:* Blink strictly operates in **Border-Box** coordinates during layout pass exchanges (`NGConstraintSpace`, `NGFragment`). Therefore, all `length_utils.cc` functions accept `border_padding` (`NGBoxStrut`) and return **border-box** sizes, even if the CSS specifies `box-sizing: content-box`.

---

### 2. Aspect-Ratio Scaling: Content-Box vs. Border-Box

**CSS Sizing Level 4 (§ 7.1)** defines that the `aspect-ratio` property applies to the box specified by `box-sizing`. 
* If `box-sizing: content-box`, the ratio is $\frac{\text{Content Inline}}{\text{Content Block}}$.
* If `box-sizing: border-box`, the ratio is $\frac{\text{Border Inline}}{\text{Border Block}}$.

#### Blink's `InlineSizeFromAspectRatio`
Blink handles this by stripping or applying the `border_padding` strut before or after multiplying by the aspect ratio, always normalizing the output back to a border-box size.

**The Mathematical Models in Blink:**

Let $B_{block}$ be the known Border-Box Block Size.
Let $BP_{inline}$ and $BP_{block}$ be the sum of borders and paddings in their respective axes.
Let $R$ be the aspect ratio ($\frac{\text{inline}}{\text{block}}$).

**Case 1: `box-sizing: content-box`**
The ratio applies *only* to the content area. Blink must strip the block border/padding, apply the ratio, and then add the inline border/padding to return a border-box size:
$$\text{Content}_{block} = \max(0, B_{block} - BP_{block})$$
$$\text{Content}_{inline} = \text{Content}_{block} \times R$$
$$\text{Result (Border-Box Inline)} = \text{Content}_{inline} + BP_{inline}$$

**Case 2: `box-sizing: border-box`**
The ratio applies to the entire border-box. However, CSS Box Model 3 states that a border-box size cannot be smaller than its borders and padding.
$$\text{Raw Border}_{inline} = B_{block} \times R$$
$$\text{Result (Border-Box Inline)} = \max(BP_{inline}, \text{Raw Border}_{inline})$$

#### Code Representation (`InlineSizeFromAspectRatio`)
```cpp
LayoutUnit InlineSizeFromAspectRatio(const NGBoxStrut& border_padding,
                                     const LogicalSize& aspect_ratio,
                                     EBoxSizing box_sizing,
                                     LayoutUnit block_size) {
  if (box_sizing == EBoxSizing::kBorderBox) {
    // Ratio applies to the whole box, clamped to minimum border/padding size.
    return std::max(
        border_padding.InlineSum(),
        LayoutUnit::FromFloatRound(block_size * aspect_ratio.inline_size / 
                                   aspect_ratio.block_size));
  }
  // kContentBox: Strip block border_padding, scale, add inline border_padding.
  block_size -= border_padding.BlockSum();
  return std::max(LayoutUnit(), LayoutUnit::FromFloatRound(
                                    block_size * aspect_ratio.inline_size /
                                    aspect_ratio.block_size)) +
         border_padding.InlineSum();
}
```
*Spec Nuance (CSS Sizing 4):* For replaced elements with an **intrinsic** aspect ratio (like an `<img>` without an explicit CSS `aspect-ratio: <ratio>`), the ratio *always* applies to the `content-box`, regardless of the `box-sizing` property. Blink handles this by passing `EBoxSizing::kContentBox` into the helper when the ratio is derived from `StyleAspectRatioType::kAuto` + intrinsic image dimensions, and only passing `style.BoxSizing()` when an explicit CSS `aspect-ratio` is used without `auto` overriding it.

---

### 3. Definite vs. Indefinite Sizes

The concepts of **Definite** and **Indefinite** sizes (CSS Sizing 3 § 2.1) are the backbone of ratio resolution.
* **Definite:** A size that can be determined without performing layout of the element's children (e.g., `100px`, or `50%` against a definite parent, or a flex/grid stretched axis).
* **Indefinite:** `auto`, `min-content`, `max-content`, or percentages resolving against an `auto`-sized parent. 

In Blink, **Indefinite** is represented by the sentinel value `kIndefiniteSize` (`LayoutUnit(-1)`).

#### Resolution Rules (CSS Sizing 4 vs. Blink)
An aspect ratio only functions if **one axis is definite and the other is `auto` (indefinite)**, OR if both are `auto` and a fallback (like available space or intrinsic size) is triggered.

1. **Block is Definite, Inline is Auto:**
   * `ResolveMainBlockLength` returns a valid `LayoutUnit` ($\ge 0$).
   * Blink sees `inline_size` is `auto`, calls `InlineSizeFromAspectRatio()`, and clamps the result using `MinMaxSizes` (which are also converted to border-box via `ComputeMinMaxInlineSizes`).
2. **Block is Indefinite, Inline is Definite:**
   * `ResolveMainBlockLength` returns `kIndefiniteSize`.
   * `InlineSizeFromAspectRatio` **cannot** be called. Instead, Blink resolves the definite inline size first, then calls `BlockSizeFromAspectRatio` to make the block size definite.
3. **Both are Definite:**
   * Aspect ratio is ignored (over-constrained). Both dimensions resolve independently via `ResolveMainInlineLength` and `ResolveMainBlockLength`.
4. **Both are Indefinite (`width: auto; height: auto`):**
   * **Non-Replaced Elements (CSS Sizing 4):** The inline size resolves as normal (usually `stretch` / `fill-available` to the parent's `AvailableSize()`). This makes the inline size **definite**. The block size is then calculated from this resolved inline size via the aspect ratio.
   * **Replaced Elements (CSS Sizing 3):** Handled specially in `ComputeReplacedSize`.

---

### 4. Deep Dive: `ComputeReplacedSize` vs. CSS Sizing 3

`ComputeReplacedSize` implements **CSS Sizing Level 3 (§ 5.2 - Intrinsic Sizes of Replaced Elements)** and **CSS 2.1 (§ 10.3.2 / § 10.6.2)**. Replaced elements can possess an intrinsic inline size, an intrinsic block size, and/or an intrinsic aspect ratio.

Blink’s `ComputeReplacedSize` takes the `NGBlockNode`, the `NGConstraintSpace` (available sizes, percentage resolution sizes), and `border_padding`, and executes a multi-branch state machine based on which sizes are definite.

#### State 1: Both CSS Inline and Block Sizes are Definite
* **W3C Spec:** Intrinsic sizes and aspect ratios are ignored. Use the specified sizes, clamped by `min-*` and `max-*`.
* **Blink:** `ResolveMainInlineLength` and `ResolveMainBlockLength` both return $\neq$ `kIndefiniteSize`. Blink applies `MinMaxSizes` and returns the `LogicalSize`.

#### State 2: One CSS Axis is Definite, the Other is Indefinite (`auto`)
* **W3C Spec:** If the element has an intrinsic aspect ratio, compute the `auto` dimension using the definite dimension and the ratio (applying `content-box` math, unless overridden by `aspect-ratio` property with `box-sizing: border-box`). Then clamp the computed dimension by its `min/max` properties. If no aspect ratio exists, use the intrinsic size for the `auto` axis, or fallback to `300px`x`150px`.
* **Blink:** 
  * Suppose Block is Definite, Inline is `auto`.
  * Blink resolves `block_size`.
  * It calls `InlineSizeFromAspectRatio(border_padding, aspect_ratio, box_sizing, block_size)`.
  * It resolves `MinMaxSizes` for the inline axis and runs `minmax.ClampSizeToMinAndMax(resolved_inline)`.

#### State 3: Both CSS Axes are Indefinite (`width: auto; height: auto`)
This is the most complex part of the CSS spec (CSS 2.1 § 10.4 & CSS Sizing 3). When both dimensions are `auto`, the aspect ratio must be preserved *while simultaneously* respecting `min-width`, `max-width`, `min-height`, and `max-height`.

* **W3C Spec (The Constraint Violation Table):** You start with the intrinsic width and height. If no intrinsic size exists (e.g., an SVG with `viewBox` but no `width`/`height`), you resolve the inline size against the containing block (stretch-fit) and derive the block size. You then check if $W$ or $H$ violates `min/max` constraints, scaling both axes proportionally depending on which constraint is more restrictive (e.g., if `W > max-width` and `H > max-height`, whichever ratio $\frac{\text{max-width}}{W}$ or $\frac{\text{max-height}}{H}$ is smaller wins).
* **Blink (`ComputeReplacedSize`):**
  1. **Obtain starting base size:** Calls `node.ComputeIntrinsicSizeInfo()`.
  2. **SVG / Ratio-only edge case:** If there is an aspect ratio, *no* intrinsic sizes, and both CSS sizes are `auto`, Blink resolves the inline size to `space.AvailableSize().inline_size` (clamped by inline min/max), and derives the block size via the aspect ratio.
  3. **Constraint Resolution (`ConstrainByMinMax`):** If intrinsic sizes exist, Blink gathers `min_max_inline` and `min_max_block`. Instead of a massive `if/else` table like the CSS 2.1 spec text, Blink uses a mathematical equivalent:
     * It converts the **block** `MinMaxSizes` into **inline** `MinMaxSizes` by running the block constraints through `InlineSizeFromAspectRatio`.
     * Now it has two sets of inline constraints: `explicit_inline_minmax` and `transferred_block_minmax`.
     * It intersects these ranges (paying special attention to the spec rule that `min` wins over `max` when they conflict) to find the exact constrained inline size, then derives the final block size from that constrained inline size.

### Summary of Architectural Differences (Spec vs. Blink)

1. **Coordinate Spaces:** The W3C specs mostly write formulas assuming `content-box` and tell implementers to "adjust for `box-sizing`." Blink's `length_utils.cc` strictly enforces **border-box** invariants. Every calculation immediately pads results with `border_padding.InlineSum()` or `BlockSum()`.
2. **Transferred Constraints (Sizing 4):** Instead of testing `w > max_w` and `h > max_h` simultaneously as described in the CSS 2.1 constraint table, Blink implements the **CSS Sizing 4 "Transferred Size" model**. It projects `min-height` and `max-height` *through* `InlineSizeFromAspectRatio` into the inline axis, resolving constraints in 1D space before projecting back to 2D.
3. **Indefinite Sentinels:** While the spec talks abstractly about "fallback to intrinsic size when indefinite," Blink relies on passing `kIndefiniteSize` (`-1`) into `ResolveMainBlockLength()`. If the return is `-1`, the control flow inside `ComputeReplacedSize` branches into the `AspectRatio` or `IntrinsicSize` fallback paths.