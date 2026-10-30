# Agent 1 Audit Report: Chromium Blink Scrollable Overflow vs. W3C CSS Overflow Module Level 3

## 1. Core Data Structures in Blink Scrollable Overflow

In Chromium's Blink rendering engine (post-LayoutNG architecture), scrollable overflow calculation and scroll offset management are distributed across LayoutNG fragment builders, physical geometry primitives, and paint-layer scrolling controllers.

### 1.1 `PhysicalRect`, `LayoutUnit`, and `ScrollOffset`
*   **`LayoutUnit`**: Blink’s subpixel layout primitive (`platform/geometry/layout_unit.h`). It is a 32-bit signed fixed-point value with 6 fractional bits ($\frac{1}{64}$ pixel precision, `kFixedPointDenominator = 64`). Arithmetic is saturating (`LayoutUnit::Max()`, `LayoutUnit::Min()`).
*   **`PhysicalRect`**: Defined in `core/layout/geometry/physical_rect.h`, it represents a rectangle in physical screen coordinates relative to an arbitrary physical origin (typically the top-left of a `PhysicalBoxFragment`'s border box).
    $$\text{PhysicalRect} = (\text{offset}: (\text{left}: \text{LayoutUnit}, \text{top}: \text{LayoutUnit}), \text{size}: (\text{width}: \text{LayoutUnit}, \text{height}: \text{LayoutUnit}))$$
    where $\text{MaxX}() = \text{left} + \text{width}$ and $\text{MaxY}() = \text{top} + \text{height}$.
*   **`ScrollOffset`**: Defined as a `gfx::Vector2dF` (`float` pair), representing the continuous scroll displacement from the `scroll_origin_`. Unlike layout structures which use `LayoutUnit`, `ScrollOffset` operates in floating-point to support smooth/composited fractional scrolling.

### 1.2 `ScrollableOverflowCalculator`
Located in `third_party/blink/renderer/core/layout/scrollable_overflow_calculator.h` (and `.cc`), this class is instantiated during fragment creation (`BoxFragmentBuilder`) or layout overflow recalculation.
*   **State Members**:
    *   `const WritingDirectionMode writing_direction_`: Encapsulates `WritingMode` (`kHorizontalTb`, `kVerticalRl`, `kVerticalLr`, `kSidewaysRl`, `kSidewaysLr`) and `TextDirection` (`kLtr`, `kRtl`).
    *   `const bool is_scroll_container_`: Determines if the current box establishes a scrolling mechanism (`overflow: auto | scroll | hidden | clip` with scrollable semantics).
    *   `const PhysicalBoxStrut padding_`: Physical padding strut of the container.
    *   `const PhysicalRect padding_rect_`: The container's physical padding box, which serves as the initial seed for the scrollable overflow rectangle.
    *   `PhysicalRect scrollable_overflow_`: The accumulator rectangle initialized to `padding_rect_`.

### 1.3 `PaintLayerScrollableArea`
Located in `third_party/blink/renderer/core/paint/paint_layer_scrollable_area.h`, this class manages the runtime scrolling state of a `LayoutBox`.
*   **Key Geometry Fields**:
    *   `PhysicalRect layout_overflow_rect_`: The scrollable overflow rectangle stored in the coordinate space of the box's physical border box (top-left = $(0,0)$).
    *   `gfx::Point scroll_origin_`: The physical pixel offset from the top-left of the border box (or padding box origin depending on phase) to the $(0,0)$ scroll offset position, determined by the `WritingDirectionMode`.
    *   `ScrollOffset scroll_offset_`: Current scroll displacement relative to `scroll_origin_`.

---

## 2. Calculation of Scrollable Overflow Rectangle

Per **W3C CSS Overflow Module Level 3, Section 3 (Scrollable Overflow)**, the scrollable overflow region is the union of several boxes bounded by the scroll container, adjusted for padding, margins, and transforms, and finally clipped in the unreachable scroll directions.

In Blink, `ScrollableOverflowCalculator` executes the following sequence:

### 2.1 Initialization (Padding Box Seed)
The calculator initializes `scrollable_overflow_` to the container’s `padding_rect_`:
$$\text{ PaddingRect} = (\text{BorderLeft}, \text{BorderTop}, \text{Width} - \text{BorderLeft} - \text{BorderRight}, \text{Height} - \text{BorderTop} - \text{BorderBottom})$$

### 2.2 Inclusion of In-Flow Children and Line Boxes
For each child `PhysicalBoxFragment` (or `FragmentItems` for inline formatting contexts):
1.  **Child Margin Box Contribution**: According to CSS Overflow L3 §3.1, the margin boxes of in-flow block-level boxes (or grid/flex items) contribute to scrollable overflow.
    However, Blink historically did not add all margins unconditionally. In LayoutNG (`ScrollableOverflowCalculator::AddBox` and `AdjustOverflowForChild`):
    *   Start with the child's border box in the parent's physical coordinate space: $R_{\text{border}} = (\text{child.offset}, \text{child.size})$.
    *   If the child is a scroll container itself, its own `ScrollableOverflow()` is **not** propagated; only its border box (plus applicable margins) contributes.
    *   If the child is **not** a scroll container, its `ScrollableOverflow()` is translated by `child.offset` and united with $R_{\text{border}}$, unless the child has `overflow: clip` (which clips overflow along the specified axes via `OverflowClipAxes`).
2.  **End-Edge Padding and Margin Synthesis (`AdjustOverflowForScrollOrigin`)**:
    In CSS Overflow L3, the padding of the scroll container is supposed to be added around the *in-flow* children's margin boxes so that scrolling to the end reveals the container's end-side padding.
    Blink implements this in `ScrollableOverflowCalculator::OverflowForChild`:
    *   For in-flow children, Blink adds the child's physical margins on the block-end and inline-end directions *plus* the scroll container's `padding_` on the block-end and inline-end edges.
    *   Negative margins on children: If a child has a negative margin that pulls its margin-box *inside* its border-box, the border-box still contributes fully (since $R_{\text{child}} = R_{\text{border}} \cup R_{\text{margin\_adjusted}} \cup R_{\text{descendant\_overflow}}$). If a negative margin pulls the child into the unreachable scroll origin region (e.g., negative `margin-top` or `margin-left` in `horizontal-tb` LTR), it is subsequently clamped during scroll origin normalization (Section 3).

### 2.3 Out-of-Flow (OOF) Positioned Descendants
For an out-of-flow positioned descendant (`position: absolute` or `fixed`) whose containing block is inside (or is) the scroll container, its layout is finalized at the containing block level (`OutOfFlowLayoutPart`).
*   When contributing to `ScrollableOverflowCalculator::AddBox`:
    *   OOF descendants **do not** include the scroll container’s end-edge padding (diverging from some interpretations of CSS Overflow L3, though matching the CSSWG resolution on absolute positioning padding inflation in certain contexts; see Section 4.4).
    *   OOF descendants' physical border boxes and their unclipped scrollable overflow trees are united into `scrollable_overflow_`.

### 2.4 Transformed Elements
Before uniting a child's overflow contribution $R_{\text{child}}$ with the container's `scrollable_overflow_`:
*   If `child.HasTransformForScrollableOverflow()` is true, Blink fetches the transformation matrix $M \in \mathbb{R}^{4 \times 4}$ (`TransformHelper::GetTransformMatrix`), which includes CSS `transform`, `translate`, `rotate`, `scale`, and `offset-path` properties, anchored at `transform-origin`.
*   The bounding box $R_{\text{child}}$ is mapped through $M$ via `gfx::Transform::MapRect(gfx::RectF(R_child))` and converted back to `PhysicalRect::EnclosingRect` (using `floor` for min-coords and `ceil` for max-coords to `LayoutUnit`).
*   **Crucial detail**: CSS animations running on the compositor do not update layout-time scrollable overflow on every frame; Blink evaluates the base/current layout transform state.

### 2.5 Exclusion of Non-Scrollable Overflow
The following visual constructs are explicitly excluded from `ScrollableOverflowCalculator` (they go into `VisualOverflow` instead):
*   `box-shadow` and `text-shadow`.
*   `outline`.
*   `border-image-outset`.
*   `filter` (e.g., `drop-shadow`, `blur` expansion) and `backdrop-filter`.
*    Glyphs overhanging their inline box ascender/descender or inline bounds (ink overflow), *except* where legacy quirks or specific ruby/emphasis annotations expand line box metrics.
*    Elements with `position: fixed` when the scroll container is not their containing block (e.g., viewport-attached fixed elements inside an inner `overflow: scroll` div).

---

## 3. Scroll Origin Offset Resolution (LTR vs. RTL / Vertical Writing Modes)

A scroll container can only scroll in the **block-end** and **inline-end** directions from its initial scroll position (`scrollOrigin`). Content overflowing in the **block-start** or **inline-start** directions is *unreachable* via scrolling and is clipped out of the scrollable overflow rectangle.

### 3.1 Physical Scrollable Directions Matrix
The two axes of a box are Horizontal ($X$, positive rightwards) and Vertical ($Y$, positive downwards).
Depending on `WritingMode` and `TextDirection`, the **Inline-End** and **Block-End** map to physical directions as follows:

| `WritingMode` | `TextDirection` | Inline Flow | Block Flow | Physical $X$ Scrollable Direction | Physical $Y$ Scrollable Direction | Initial Origin Corner |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `horizontal-tb` | `ltr` | $\rightarrow (+X)$ | $\downarrow (+Y)$ | Right ($+X$) | Down ($+Y$) | Top-Left |
| `horizontal-tb` | `rtl` | $\leftarrow (-X)$ | $\downarrow (+Y)$ | Left ($-X$) | Down ($+Y$) | Top-Right |
| `vertical-rl` | `ltr` | $\downarrow (+Y)$ | $\leftarrow (-X)$ | Left ($-X$) | Down ($+Y$) | Top-Right |
| `vertical-rl` | `rtl` | $\uparrow (-Y)$ | $\leftarrow (-X)$ | Left ($-X$) | Up ($-Y$) | Bottom-Right |
| `vertical-lr` | `ltr` | $\downarrow (+Y)$ | $\rightarrow (+X)$ | Right ($+X$) | Down ($+Y$) | Top-Left |
| `vertical-lr` | `rtl` | $\uparrow (-Y)$ | $\rightarrow (+X)$ | Right ($+X$) | Up ($-Y$) | Bottom-Left |
| `sideways-rl` | `ltr` | $\downarrow (+Y)$ | $\leftarrow (-X)$ | Left ($-X$) | Down ($+Y$) | Top-Right |
| `sideways-rl` | `rtl` | $\uparrow (-Y)$ | $\leftarrow (-X)$ | Left ($-X$) | Up ($-Y$) | Bottom-Right |
| `sideways-lr` | `ltr` | $\uparrow (-Y)$ | $\rightarrow (+X)$ | Right ($+X$) | Up ($-Y$) | Bottom-Left |
| `sideways-lr` | `rtl` | $\downarrow (+Y)$ | $\rightarrow (+X)$ | Right ($+X$) | Down ($+Y$) | Top-Left |

Let two boolean predicates define whether the positive physical axis is the scrollable (end) direction:
*   $\text{HasLeftOverflow}(W, D) \iff X\text{-scrollable direction is } -X$:
    True when $(W = \text{horizontal-tb} \land D = \text{rtl}) \lor (W \in \{\text{vertical-rl}, \text{sideways-rl}\})$.
*   $\text{HasTopOverflow}(W, D) \iff Y\text{-scrollable direction is } -Y$:
    True when $(W \in \{\text{vertical-rl}, \text{vertical-lr}, \text{sideways-rl}\} \land D = \text{rtl}) \lor (W = \text{sideways-lr} \land D = \text{ltr})$.

### 3.2 Clamping Unreachable Overflow (`ScrollableOverflowCalculator::Result`)
Let $P = (P_x, P_y, P_w, P_h)$ be the `padding_rect_` of the scroll container, with $P_{\text{maxX}} = P_x + P_w$ and $P_{\text{maxY}} = P_y + P_h$.
Let $U = (U_x, U_y, U_w, U_h)$ be the raw accumulated union rectangle before clamping, with $U_{\text{maxX}} = U_x + U_w$ and $U_{\text{maxY}} = U_y + U_h$. Since $U$ was initialized to $P$, we are guaranteed $U_x \le P_x$, $U_y \le P_y$, $U_{\text{maxX}} \ge P_{\text{maxX}}$, and $U_{\text{maxY}} \ge P_{\text{maxY}}$.

If `is_scroll_container_` is true, Blink clamps the unreachable start edges to the `padding_rect_` edges:
*   **Horizontal Clamping**:
    *   If $\neg \text{HasLeftOverflow}(W, D)$ (i.e., scrolling rightwards $+X$):
        The left edge cannot be scrolled to if it is less than $P_x$.
        $$R_x = P_x, \quad R_{\text{maxX}} = \max(P_{\text{maxX}}, U_{\text{maxX}}) = U_{\text{maxX}}$$
    *   If $\text{HasLeftOverflow}(W, D)$ (i.e., scrolling leftwards $-X$):
        The right edge cannot be scrolled past $P_{\text{maxX}}$.
        $$R_x = \min(P_x, U_x) = U_x, \quad R_{\text{maxX}} = P_{\text{maxX}}$$
*   **Vertical Clamping**:
    *   If $\neg \text{HasTopOverflow}(W, D)$ (i.e., scrolling downwards $+Y$):
        $$R_y = P_y, \quad R_{\text{maxY}} = \max(P_{\text{maxY}}, U_{\text{maxY}}) = U_{\text{maxY}}$$
    *   If $\text{HasTopOverflow}(W, D)$ (i.e., scrolling upwards $-Y$):
        $$R_y = \min(P_y, U_y) = U_y, \quad R_{\text{maxY}} = P_{\text{maxY}}$$

The resulting scrollable overflow rect is $R = (R_x, R_y, R_{\text{maxX}} - R_x, R_{\text{maxY}} - R_y)$.

### 3.3 `scroll_origin_` Calculation