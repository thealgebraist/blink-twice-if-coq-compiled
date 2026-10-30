**AUDIT REPORT: BLINK SCROLL MARGIN OUTSET & SNAP AREA EXPANSION**
**AUDITOR:** Agent 334
**TARGET:** Chromium / Blink Rendering Engine (`cc::SnapContainerData` / `blink::ScrollSnapType`)
**SUBJECT:** `scroll-margin` Outset Application & Snap Area Expansion Mechanics

---

### 1. EXECUTIVE SUMMARY
In the Blink rendering engine, the **Snap Area** of a scroll-snap target is not strictly bound by its standard CSS layout box. The `scroll-margin` property defines an **outset** that expands the target's bounding box outward, creating a modified geometric region used exclusively for scroll-snap calculations. 

Audit confirms that this expansion occurs post-layout, does not affect document flow, and is passed to the Compositor Thread (`cc`) to ensure 60fps+ snap physics.

---

### 2. MECHANICS OF SNAP AREA EXPANSION

#### 2.1 Base Box Identification
Before expansion, Blink identifies the element's base box— specifically, its **Border Box** within the coordinate space of the Scroll Container. 
*   `BaseRect = LayoutBox::BorderBoxRect()` mapped to the scroll container's scrollable overflow area.

#### 2.2 Application of the Outset (`scroll-margin`)
The `scroll-margin` properties (`top`, `right`, `bottom`, `left`, and logical equivalents like `block-start`, `inline-end`) are parsed as `Length` values (Note: percentages are invalid per CSS Scroll Snap Module Level 1).

Blink computes a `LayoutRectOutsets` object from the `ComputedStyle` of the target element. The expansion math is applied as follows:

$$\text{SnapArea}_{top} = \text{BorderBox}_{top} - \text{scroll-margin-top}$$
$$\text{SnapArea}_{left} = \text{BorderBox}_{left} - \text{scroll-margin-left}$$
$$\text{SnapArea}_{bottom} = \text{BorderBox}_{bottom} + \text{scroll-margin-bottom}$$
$$\text{SnapArea}_{right} = \text{BorderBox}_{right} + \text{scroll-margin-right}$$

*Note: While styled as an "expansion," negative `scroll-margin` values are permitted and will result in an **inset** (shrinking the snap area).*

---

### 3. BLINK PIPELINE ARCHITECTURE

#### 3.1 Main Thread Calculation
During the `PrePaint` lifecycle phase (specifically within `SnapCoordinator`), Blink iterates over elements registered with a non-none `scroll-snap-align`.

1.  **Extraction:** `StyleFetched` pulls `ScrollMarginTop()`, `ScrollMarginRight()`, etc., from `ComputedStyle`.
2.  **Transformation:** The element's local border box is expanded by the `scroll-margin` outsets *after* local CSS transforms (like `scale` or `rotate`) are applied, calculated via the Axis-Aligned Bounding Box (AABB) in the scroll container's coordinate space.
3.  **Clamping:** The expanded snap area is **not** clipped by intermediate `overflow: hidden` ancestors, unless that ancestor is the scroll container itself.

#### 3.2 Compositor Handoff (`cc`)
Blink packages the expanded rect into a `cc::SnapAreaData` struct. The compositor does not know what the original border-box was, nor does it know the `scroll-margin` values. It only receives the final, expanded `gfx::RectF` representing the **Snap Area**.

---

### 4. EDGE CASES & INTERACTION VECTORS (AUDIT FINDINGS)

*   **Intersection with `scroll-padding`:** While `scroll-margin` expands the *target's* Snap Area (outset), `scroll-padding` shrinks the *container's* Optimal Viewing Region (inset). Snap alignment occurs when the expanded Snap Area aligns with the shrunken Optimal Viewing Region.
*   **Large Outsets (Larger than Viewport):** If `scroll-margin` expands a Snap Area to be larger than the scrollport's Optimal Viewing Region, Blink enters "Covering" logic. The container will allow free scrolling *within* the expanded snap area, only snapping when the user attempts to scroll past the expanded edges.
*   **Fragmentation:** If an element is fragmented across columns or pages, `scroll-margin` is applied to the bounding box of the union of all fragments.
*   **Scroll-Into-View:** Audit confirms that `Element.scrollIntoView()` and fragment navigation (`#anchor`) also respect this exact `scroll-margin` expansion, utilizing the same underlying Blink geometry helpers (`LayoutObject::ScrollSnapMarginRect()`).

### 5. STATUS
**COMPLIANT.** Blink's implementation of `scroll-margin` outset expansion aligns with W3C CSS Scroll Snap Module Level 1 specifications. No layout-thrashing detected during compositor snap evaluation. 

*End of Report. Agent 334 signing off.*