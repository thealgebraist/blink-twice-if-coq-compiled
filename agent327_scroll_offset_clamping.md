**AUDIT REPORT: BLINK SCROLL OFFSET CLAMPING BOUNDS**
**Auditor:** Agent 327
**Target:** Chromium / Blink Rendering Engine (`blink::ScrollableArea` & `cc::ScrollNode`)
**Subject:** Scroll Offset Clamping Bounds and Edge-Case Vectors

---

### 1. Executive Summary
In the Blink rendering engine, scroll offset clamping is the mechanism that restricts a scroll container's current position (`scroll_offset`) within valid geometric boundaries. Failure to clamp accurately results in rendering artifacts, unreachable content, or layer-compositing desynchronization between the Blink main thread and the Chromium Compositor (`cc`). 

The fundamental invariant for any scrollable area is:
$$\text{Clamp}(\text{offset}) = \max(\text{MinimumScrollOffset}, \min(\text{offset}, \text{MaximumScrollOffset}))$$

---

### 2. Core Coordinate Spaces & Primitives
Blink handles scrolling using two distinct metrics, bridged by the **ScrollOrigin**:

*   **Scroll Offset (`gfx::PointF` / `ScrollOffset`):** The distance the content has moved from its initial, un-scrolled position (Origin `0,0`). This is the standard DOM representation (`window.scrollX`, `element.scrollTop`).
*   **Scroll Position:** The physical coordinates relative to the top-left of the `contents_size`.
*   **Conversion Invariant:** $\text{ScrollOffset} = \text{ScrollPosition} - \text{ScrollOrigin}$

---

### 3. Bound Definitions

#### A. Minimum Scroll Offset (`MinimumScrollOffset`)
The lower bound of the clamping operation.
*   **Standard LTR/Top-to-Bottom:** The minimum offset is `[0, 0]`.
*   **RTL / Writing-Mode Variations:** When `writing-mode` is vertical-rl or `direction` is `rtl`, the `ScrollOrigin` shifts to the right or bottom edge of the container. Consequently, scrolling "backwards" (left or up) results in **negative** scroll offsets.
*   **Formula:** 
    $$\text{MinOffset} = -\text{ScrollOrigin}$$

#### B. Maximum Scroll Offset (`MaximumScrollOffset`)
The upper bound of the clamping operation. It is the total scrollable overflow distance beyond the origin.
*   **Standard LTR/Top-to-Bottom:** 
    $$\text{MaxOffset} = \max(0, \text{ContentsSize} - \text{VisibleSize})$$
*   **Universal Formula (Accounting for `ScrollOrigin`):**
    $$\text{MaxOffset} = \max(\text{ScrollOrigin}, \text{ContentsSize} - \text{VisibleSize}) - \text{ScrollOrigin}$$
*   *Note:* If `ContentsSize` $\le$ `VisibleSize`, the maximum scroll offset collapses to `[0, 0]`, locking the container.

---

### 4. Architectural Modifiers & Edge Cases

During the audit of `PaintLayerScrollableArea` and `RootFrameViewport`, several factors were identified that dynamically mutate the clamping bounds:

#### 1. Fractional Scroll Offsets & Subpixel Layout
*   **Internal State:** Blink stores scroll offsets internally as `gfx::PointF` (floating-point) to support smooth animations, high-DPI displays, and pinch-zoom.
*   **Clamping:** Bounds (`MinimumScrollOffset` and `MaximumScrollOffset`) are traditionally calculated using floored or snapped layout units (`LayoutUnit` $\rightarrow$ `int`), though fractional bounds exist when FractionalScrollOffsets are enabled.
*   **Audit Risk:** If `ContentsSize` is fractional (e.g., `1000.6px`) and `VisibleSize` is `500px`, integer truncation of the max bound to `500px` leaves `0.6px` of content permanently clipped and unreachable. Blink uses `PixelSnappedContentsSize` to mitigate this, snapping edges before calculating the delta.

#### 2. Visual vs. Layout Viewport (`RootFrameViewport`)
Clamping at the document root is bifurcated:
*   **Layout Viewport (`FrameView`):** Clamped by the CSS layout bounds and affected by the browser's dynamic UI (e.g., mobile URL bar height).
*   **Visual Viewport (`VisualViewport`):** Clamped by the scaled pinch-zoom dimensions.
    $$\text{VisualMaxOffset} = \text{LayoutViewportSize} - \frac{\text{VisualViewportSize}}{\text{PageScaleFactor}}$$
*   **Clamping Order:** A scroll delta applied to `RootFrameViewport` is distributed (usually to the Visual Viewport first, then Layout, or vice-versa depending on the scroll type) and clamped independently at both levels.

#### 3. Scrollbars and `box-sizing`
The presence of non-overlay scrollbars directly mutates `VisibleSize`:
$$\text{VisibleWidth} = \text{ClientBoxWidth} - \text{VerticalScrollbarWidth}$$
If a layout change triggers `overflow: auto` to spawn a scrollbar, `VisibleSize` shrinks, `MaximumScrollOffset` increases, and an immediate re-clamp (`ClampScrollOffsetAfterLayout`) is required.

#### 4. Elastic Overscroll (Mac / iOS / Android)
*   **Blink Main Thread:** *Strictly* clamps offsets. Blink never sees out-of-bounds offsets from overscroll.
*   **Compositor (`cc`):** Allows the active tree's scroll offset to temporarily violate `Min/Max` bounds via `elastic_overscroll_` vectors (or Android glow effects/stretch transformations), which are visually applied as a transform matrix post-clamping, rather than mutating the true `ScrollNode` offset bounds.

#### 5. Browser Zoom (Page Zoom vs. Pinch Zoom)
*   **Page Zoom (Ctrl +/-):** Scales CSS pixels to DIPs (Device Independent Pixels). `ContentsSize` and `VisibleSize` are scaled by the `LayoutZoomFactor`. Clamping happens in the zoomed coordinate space.
*   **DOM Exposure:** When `element.scrollTop` is queried, the clamped zoomed offset is divided by the zoom factor, which can introduce floating-point rounding discrepancies at the max boundary.

---

### 5. Lifecycle of a Clamping Operation

1.  **Input/Mutation:** Scroll requested via `ScrollableArea::SetScrollOffset`, user input (`cc::InputHandler`), or DOM mutation.
2.  **Geometry Update:** `PaintLayerScrollableArea::UpdateScrollDimensions()` computes `ScrollOrigin`, `ContentsSize`, and `VisibleSize` at the end of the Layout phase.
3.  **Deferred Clamping:** During layout, scroll clamping is temporarily suppressed (`ScrollAnchor` may adjust the offset first to prevent visual jumps).
4.  **Execution:** `PaintLayerScrollableArea::ClampScrollOffsetAfterLayout()` executes:
    ```cpp
    ScrollOffset ClampedScrollOffset(const ScrollOffset& offset) {
      return offset.ExpandedTo(MinimumScrollOffset())
                   .ShrunkTo(MaximumScrollOffset());
    }
    ```
5.  **Commit:** The clamped offset is pushed to the `PropertyTreeState` (`ScrollTranslation` transform node) and committed to the Compositor thread.

*End of Audit Report. Awaiting further directives, Agent 327 out.*