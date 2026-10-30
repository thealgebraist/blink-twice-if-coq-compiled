**AUDIT LOG: AGENT 335**
**SUBJECT:** Chromium/Blink Rendering Engine – CSS Scroll Snap & Padding Inset
**COMPONENT:** `blink::SnapCoordinator` / `cc::SnapContainerData` / `LayoutBox`
**FOCUS:** Snapport Shrinkage Mechanics via `scroll-padding`

---

### 1. EXECUTIVE SUMMARY
In the Blink layout and compositing pipeline, **snapport shrinkage** is the geometric reduction of the optimal viewing region of a scroll container. While the *visual viewport* (or scrollport) defines the literal boundaries of the scrollable area, the *snapport* is the inner box against which `scroll-snap-align` positions of child elements (`snap areas`) are calculated. 

Applying `scroll-padding` acts as a directional inward inset on the scrollport, shrinking the effective snapport to prevent snapped elements from being obscured by fixed-position overlays (e.g., sticky headers, toolbars).

---

### 2. MATHEMATICAL MODEL OF SNAPPORT SHRINKAGE

Let the **Scrollport ($S$)** be defined in the local coordinate space of the `LayoutBox` (excluding scrollbars):
$$S = \{ x: 0, \quad y: 0, \quad w: \text{ClientWidth}, \quad h: \text{ClientHeight} \}$$

Let the resolved **`scroll-padding` Insets ($P$)** be defined as:
$$P = \{ P_{\text{top}}, \quad P_{\text{right}}, \quad P_{\text{bottom}}, \quad P_{\text{left}} \}$$

The resulting **Snapport ($S_{\text{snap}}$)** undergoes shrinkage transformation:
*   $S_{\text{snap}}.x = S.x + P_{\text{left}}$
*   $S_{\text{snap}}.y = S.y + P_{\text{top}}$
*   $S_{\text{snap}}.w = \max(0, \quad S.w - (P_{\text{left}} + P_{\text{right}}))$
*   $S_{\text{snap}}.h = \max(0, \quad S_{\text{h}} - (P_{\text{top}} + P_{\text{bottom}}))$

*Note: In Blink, these values are represented using `LayoutUnit` (fixed-point fractional pixels) during layout, and converted to `gfx::RectF` for the compositor thread (`cc`).*

---

### 3. BLINK IMPLEMENTATION PIPELINE

#### A. Style Resolution (`ComputedStyle`)
*   Blink parses `scroll-padding-*` (or logical equivalents `scroll-padding-block`, `scroll-padding-inline`).
*   Writing modes and text directions are resolved via `PhysicalToLogical` mappings to yield physical `Length` values (`scroll_padding_top_`, etc.).
*   `auto` resolves to `0px` by default in standard web contexts, though Blink allows internal UA heuristics to inject non-zero values if needed.

#### B. Layout & Percentage Resolution (`ScrollableArea` / `SnapCoordinator`)
*   Percentages in `scroll-padding` are resolved against the **corresponding dimension of the scrollport** (unlike standard CSS `padding`, which resolves all percentages against the inline width).
    *   `scroll-padding-top: 10%` $\rightarrow 0.10 \times \text{Scrollport Height}$.
    *   `scroll-padding-left: 10%` $\rightarrow 0.10 \times \text{Scrollport Width}$.
*   The `SnapCoordinator` extracts the base rect via `ScrollableArea::VisibleContentRect()` (ignoring scrollbars) and applies `MinimumValueForLength()` to calculate the `gfx::OutsetsF` (or insets) that shrink the rect.

#### C. Compositor Handoff (`cc::SnapContainerData`)
*   Blink constructs a `cc::SnapContainerData` struct.
*   The shrunken `gfx::RectF` is stored as the `rect_` property of the `SnapContainerData`.
*   When the compositor thread handles an active scroll gesture (`cc::InputHandler`), it evaluates snap targets (`cc::SnapAreaData`) against this pre-shrunken `rect_`, completely agnostic to the original scrollport dimensions.

---

### 4. EDGE CASES & DEGENERATE SHRINKAGE AUDITS

**Case 335-A: Over-Shrinkage (Insets > Scrollport Dimensions)**
*   **Condition:** $P_{\text{left}} + P_{\text{right}} > S.w$ or $P_{\text{top}} + P_{\text{bottom}} > S.h$.
*   **Blink Behavior:** The snapport width/height clamps to `0.0f` (`gfx::RectF` prevents negative dimensions).
*   **Alignment Impact:** 
    *   `start` alignment continues to snap to $S.x + P_{\text{left}}$.
    *   `end` alignment snaps to $S.w - P_{\text{right}}$. (Note: In an over-shrunk state, the `end` line is now geometrically *before* the `start` line).
    *   `center` alignment resolves to the midpoint between the inverted `start` and `end` lines: 
        $$\text{Center} = \frac{(P_{\text{left}}) + (S.w - P_{\text{right}})}{2}$$

**Case 335-B: Large Snap Areas (Snap Area > Shrunken Snapport)**
*   **Condition:** A child element's snap area (modified by `scroll-margin`) is larger than the shrunken $S_{\text{snap}}$, even if it was smaller than the original $S$.
*   **Blink Behavior:** Per CSS Scroll Snap Module Level 1 specs, if the snap area is larger than the snapport, the container allows free scrolling *within* the element's bounds, only snapping when the edges of the element cross the edges of the shrunken snapport, preventing unreachable content.

**Case 335-C: Dynamic Viewport Units (`svh`, `lvh`, `dvh`) & URL Bar Retraction**
*   **Condition:** On mobile platforms (Android), the hiding/showing of the top URL bar dynamically alters the root scrollport height ($S.h$).
*   **Blink Behavior:** Percentage-based `scroll-padding` or `dvh` values trigger a `SnapContainerData` update on resize. If fixed `px` insets are used, the absolute inset remains static, meaning the *ratio* of snapport-to-scrollport increases as the URL bar hides.

**Case 335-D: Root Scroller vs. Sub-scrollers (Virtual Keyboard)**
*   **Condition:** An OS virtual keyboard overlays the bottom of the screen.
*   **Blink Behavior:** Depending on the `VirtualKeyboard` API setting (`overlays-content`), Blink may either shrink the layout viewport directly OR keep the layout viewport static and rely on the developer's `env(keyboard-inset-height)` injected into `scroll-padding-bottom` to manually induce snapport shrinkage.

---

### 5. AUDIT CONCLUSION
Blink’s handling of snapport shrinkage via `scroll-padding` is strictly compliant with the W3C CSS Scroll Snap specification. The transformation occurs prior to compositor thread serialization, ensuring 60/120fps thread-safe snap evaluations without main-thread layout thrashing during active scroll gestures. 

**STATUS:** *Audit Complete. Waiting for next directive.*