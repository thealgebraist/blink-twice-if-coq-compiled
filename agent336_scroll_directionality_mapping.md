**AUDIT LOG: AGENT 336**
**SUBJECT:** Blink Rendering Engine – Scroll Directionality & Orthogonal Coordinate Mapping
**MODULE:** `third_party/blink/renderer/core/layout/` & `core/page/scrolling/`

---

### 1. Executive Summary
This audit details the coordinate mapping architecture within the Blink rendering engine when handling scroll containers across orthogonal writing modes. Blink abstracts physical screen coordinates from CSS logical coordinates to resolve scroll offsets, scrollorigins, and scrollbar mechanics across mixed-directionality DOM trees. 

### 2. Core Coordinate Spaces
Blink utilizes two primary coordinate spaces during layout and compositing (`LayoutNG` / ` Blink Compositor`):

*   **Physical Coordinates (`PhysicalOffset`, `PhysicalSize`, `PhysicalRect`):** Anchored unconditionally to the top-left of the box. `X` increases rightwards; `Y` increases downwards. Used by Paint, Compositing (`cc`), and platform input events.
*   **Logical Coordinates (`LogicalOffset`, `LogicalSize`, `LogicalRect`):** Anchored to the `block-start` and `inline-start` of the box, dictated by the element's `writing-mode` and `direction` properties.
    *   `inline_offset`: Progression along the text line.
    *   `block_offset`: Progression perpendicular to the text line (line-stacking direction).

### 3. The Orthogonal Matrix
An "orthogonal flow" occurs when a child element has a `writing-mode` perpendicular to its parent (e.g., a `vertical-rl` child inside a `horizontal-tb` scroll container). 

Blink utilizes `WritingDirectionMode` (combining `WritingMode` and `TextDirection`) via `WritingModeConverter` to translate between spaces.

| `writing-mode` | `direction` | Inline Base (`inline-start`) | Block Base (`block-start`) | Physical Scroll X Mapping | Physical Scroll Y Mapping |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`horizontal-tb`** | `ltr` | Left ($\rightarrow$) | Top ($\downarrow$) | $+Inline$ | $+Block$ |
| **`horizontal-tb`** | `rtl` | Right ($\leftarrow$) | Top ($\downarrow$) | $-Inline$ | $+Block$ |
| **`vertical-rl`** | `ltr` | Top ($\downarrow$) | Right ($\leftarrow$) | $-Block$ | $+Inline$ |
| **`vertical-rl`** | `rtl` | Bottom ($\uparrow$) | Right ($\leftarrow$) | $-Block$ | $-Inline$ |
| **`vertical-lr`** | `ltr` | Top ($\downarrow$) | Left ($\rightarrow$) | $+Block$ | $+Inline$ |
| **`vertical-lr`** | `rtl` | Bottom ($\uparrow$) | Left ($\rightarrow$) | $+Block$ | $-Inline$ |
| **`sideways-rl`** | `ltr` | Top ($\downarrow$) | Right ($\leftarrow$) | $-Block$ | $+Inline$ |
| **`sideways-lr`** | `ltr` | Bottom ($\uparrow$) | Left ($\rightarrow$) | $+Block$ | $-Inline$ |

*(Note: Arrows indicate the direction of positive layout progression).*

### 4. Scroll Coordinate Mechanics (`PaintLayerScrollableArea`)
When auditing scroll containers, Blink tracks three distinct vector representations to reconcile CSSOM specifications with the Compositor (`cc::ScrollNode`):

#### A. Scroll Origin (`scroll_origin_`)
The physical coordinate within the `ScrollableArea` corresponding to the logical `(0, 0)` start point.
*   In `horizontal-tb` (`ltr`), the Scroll Origin is `(0, 0)` (Top-Left).
*   In `vertical-rl` (`ltr`), content begins at the top-right and expands leftwards. If the `scrollWidth` is 1000px and the `clientWidth` is 400px, the Scroll Origin is physically at `X = 600, Y = 0`.

#### B. Scroll Position (`ScrollPosition`)
The physical offset from the top-left of the scrollable content rect. It is **always positive**, ranging from `(0, 0)` to `(maximum_scroll_offset_x, maximum_scroll_offset_y)`. The compositor operates strictly in `ScrollPosition` space.

#### C. Scroll Offset (`ScrollOffset` / CSSOM `scrollLeft`, `scrollTop`)
The delta from the `ScrollOrigin`.Per the CSSOM View specification, `scrollLeft` and `scrollTop` become **negative** when scrolling in a leftward or upward progression.

**The Conversion Formula inside Blink:**
$$\text{ScrollPosition} = \text{ScrollOrigin} + \text{ScrollOffset}$$

**Example Audit (`vertical-rl` container, overflow along block axis):**
1. Container width: 400px. Content width: 1000px.
2. `ScrollOrigin.x` = $1000 - 400 = 600$.
3. Initial state (unscrolled): `ScrollOffset.x` (`scrollLeft`) = $0$. `ScrollPosition.x` = $600$.
4. User scrolls fully to the left (to the end of the block flow):
   * `ScrollOffset.x` (`scrollLeft`) = $-600$.
   * `ScrollPosition.x` = $600 + (-600) = 0$.

### 5. Orthogonal Layout & Overflow Propagation
When a child is orthogonal to its scroll container, Blink executes specific layout passes in `LayoutNG`:

1.  **Min/Max Sizes Dependency:** An orthogonal child's `inline-size` (e.g., height in `vertical-rl`) depends on the parent's `block-size` (height in `horizontal-tb`). If the parent has an `auto` height, Blink resolves this using the initial containing block (ICB) size as a fallback constraint before computing layout overflow.
2.  **Coordinate Transposition:** When calculating `LayoutOverflow` for the parent `ScrollableArea`, the child’s `LogicalRect` is first converted to a `PhysicalRect` using the **child's** `WritingModeConverter`. 
3.  **Parent Ingestion:** The parent ingests the child's `PhysicalRect` and converts it into the **parent's** `LogicalRect` space to determine if scrollbars are triggered.
4.  **Negative Overflow Suppression:** If an orthogonal child overflows into the physical top or left of a `horizontal-tb` (`ltr`) container, Blink clamps the playable scroll range. Content overflowing past the `block-start` or `inline-start` edge of the *scroll container's* writing mode is unreachable via scrolling (per CSS Overflow spec).

### 6. Input Routing (Wheel/Touch to Scroll)
When a `WheelEvent` (physical $\Delta X, \Delta Y$) hits the compositor:
1.  **Physical Mapping:** By default, physical $\Delta Y$ maps to vertical scrollbars, and $\Delta X$ maps to horizontal scrollbars, regardless of writing mode.
2.  **Axis Auto-Shift (Vertical Writing Modes):** If an element has `writing-mode: vertical-rl` or `vertical-lr`, and has **no vertical overflow** (`overflow-y: hidden` or content fits vertically), Blink's `ScrollManager` intercepts vertical mouse wheel deltas ($\Delta Y$) and remaps them to the horizontal axis ($\Delta X$) to allow natural reading-progression scrolling along the block axis.

---
**STATUS:** Audit Complete. Orthogonal mapping invariants verified against Blink LayoutNG pipeline.