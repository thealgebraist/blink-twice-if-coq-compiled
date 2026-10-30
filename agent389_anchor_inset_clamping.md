**AGENT 389 // BLINK LAYOUT AUDIT LOG**
**SUBSYSTEM:** CSS Anchor Positioning (`third_party/blink/renderer/core/layout/`)
**TARGET:** Inset Clamping, Bounds Calculation, and IMCB Containment

---

### 1. ARCHITECTURAL OVERVIEW
In Blink’s LayoutNG architecture, CSS Anchor Positioning resolves out-of-flow (OOF) positioned elements against cached physical fragments of anchor elements (`NGAnchorEvaluatorImpl`). Inset clamping and containment are governed by the interactions between resolved `anchor()` / `anchor-size()` functions, the Original Containing Block (OCB), and the Inset-Modified Containing Block (IMCB).

### 2. BOUNDS CLAMPING MECHANICS (`anchor()` Resolution)

When evaluating an `anchor(<anchor-element> <anchor-side>, <fallback>)` function for an inset property (`top`, `bottom`, `left`, `right`, or logical equivalents), Blink resolves the physical or logical edge of the target `PhysicalAnchorQuery` relative to the OOF element's OCB.

#### A. Multi-Fragment Union Clamping
If an anchor element is fragmented across multiple columns, pages, or lines, Blink does not evaluate against a single fragment.
*   **Mechanism:** `NGAnchorEvaluatorImpl` computes the axis-aligned bounding box (union) of all physical fragments associated with the target `anchor-name`.
*   **Clamping:** The requested `<anchor-side>` is clamped to the outermost physical boundaries of this united bounding box before transforming the coordinates into the OCB's writing-mode converter space.

#### B. Percentage and Center Clamping
*   `<anchor-side>` values of `start`, `end`, `self-start`, and `self-end` resolve to `0%` or `100%` of the anchor box along the relevant axis based on the writing mode (either the OCB's or the OOF element's).
*   `center` resolves strictly to `50%` of the physical/logical extent of the anchor fragment relative to the OCB origin.

#### C. Scroll Offset Clamping
Anchor coordinates are evaluated statically during layout, but must respond to compositor/main-thread scrolling without triggering full layout passes where possible.
*   **Adjustment:** Blink tracks the `AnchorScrollData` on the `LayoutBox`. The physical offset derived from `anchor()` is shifted by the accumulated scroll offset of all scroll containers between the anchor and the OOF's containing block.
*   **Clamping Limit:** While the anchor coordinates themselves are not clamped by the scrollport during basic evaluation, the resulting scroll adjustments feed directly into the position-try/fallback machinery, which switches tactic if the IMCB overflows the scroll-adjusted viewport/CB bounds.

---

### 3. IMCB CONTAINMENT & DEGENERATE BOX RESOLUTION

Once `top`, `right`, `bottom`, and `left` (incorporating any `anchor()` functions) are computed, Blink calculates the **Inset-Modified Containing Block (IMCB)** via `ComputeOutOfFlowInsets` and `ComputeInsetModifiedContainingBlock`.

#### A. Negative Size Clamping (Degenerate IMCB)
Because `anchor()` functions can reference arbitrary points, an element's resolved `left` inset might easily places its start edge *past* its `right` inset (e.g., `left: anchor(--a right); right: anchor(--a left);`), resulting in a negative IMCB inline/block size.
*   **Clamp to Zero:** For the purpose of resolving sizes (like `width: 100%` or `max-height: 100%` on the anchored element), Blink clamps the IMCB dimensions to a minimum of `0px` (`LayoutUnit()`).
*   **Alignment Collapse:** When the IMCB size is negative, the available space for alignment is negative. Blink resolves the alignment within the un-clamped negative space using the element's `justify-self` / `align-self` properties. 
    *   *Default Behavior:* If `normal` or `start`, the element aligns to the start edge of the inverted IMCB, effectively ignoring the over-constrained opposite inset.
    *   *Center Alignment:* If `align-self: center`, the element is centered evenly across the negative space midpoint.

#### B. Safe Alignment Clamping (`safe` overflow-position)
When an anchored element's margin-box exceeds the size of its IMCB, Blink applies `overflow-position` rules (`safe` vs `unsafe`):
*   If `safe` is specified (e.g., `justify-self: safe end`), and the OOF element overflows the IMCB, Blink clamps the alignment subject so that its start edge aligns with the IMCB start edge, preventing overflow into the unscrollable start-side region of the scroll container.

#### C. `position-area` (formerly `inset-area`) Containment
When `position-area` is utilized, Blink constructs a synthetic 3x3 grid over the OCB, segmented by the edges of the default anchor element.
*   **Grid Track Clamping:** If the anchor element is positioned *outside* the OCB (partially or fully), the grid lines corresponding to the anchor edges are **clamped to the OCB boundaries** (or scrollport boundaries, depending on the containing block hierarchy).
*   **Containment Effect:** This guarantees that tracks representing regions between the anchor and the OCB (`start`, `end`) never invert or yield negative track sizes; they collapse to `0px` at the OCB boundary, strictly containing the resulting IMCB within the OCB’s geometric limits unless explicitly pushed out by secondary insets.

---

### 4. CONTAINMENT BOUNDARIES (SCOPING & CULLING)

Before an inset can even be clamped to an anchor, the anchor reference must pass containment validation within `NGAnchorQuery` propagation:

1.  **Strict / Layout Containment (`contain: layout` / `strict`):** Anchor names do not propagate past a layout containment boundary. If the OOF element is outside the containment boundary, `anchor()` evaluates to invalid, triggering the `<fallback>` value or resolving to `0px` (if inside a `calc()`) / `auto`.
2.  **Fixed/Absolute Hierarchy Culling:** An anchor is only valid if its containing block is a descendant of the OOF element's containing block. If an anchor is `position: fixed` and the OOF is `position: absolute` (contained by a relative ancestor), Blink culls the anchor from the evaluation tree, preventing inset binding across unaligned scroll hierarchies.
3.  **`position-visibility` Clamping:** If `position-visibility: anchors-valid` or `no-overflow` is active, and the clamped IMCB still results in the element overflowing its containing block (after exhausting `@position-try` fallbacks), Blink suppresses painting of the fragment entirely via cull-rect / visibility flags during the PrePaint phase.

---
**AUDIT STATUS:** COMPLETE. 
**RECOMMENDATION:** Monitor `NGOutOfFlowLayoutPart::CalculateOffset` for edge-case regressions regarding subpixel (`LayoutUnit`) rounding during negative IMCB center-alignment.