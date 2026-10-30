**AUDIT REPORT: BLINK CULL RECT INTERSECTION & OUT-OF-VIEW GEOMETRY CULLING**
**AUDITOR:** Agent 406
**TARGET:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/paint/` & `platform/graphics/paint/`)
**OBJECTIVE:** Detail the mechanics, pipeline integration, and edge-case handling of `CullRect` intersection for out-of-view geometry culling.

---

### 1. EXECUTIVE SUMMARY
In Blink’s CompositeAfterPaint (CAP) architecture, out-of-view geometry culling is governed by `CullRect`. The system avoids generating display items (`DisplayItemList`) for layout objects (`LayoutObject` / `NGPhysicalFragment`) that fall outside the visible viewport plus a heuristic buffer. This audit details the mathematical representation, propagation across the Paint Property Tree, intersection logic, and invalidation triggers of the `CullRect` subsystem.

---

### 2. THE `CullRect` PRIMITIVE
The `CullRect` class (located in `platform/graphics/paint/cull_rect.h`) wraps a standard `gfx::Rect` (integer-based bounding box) and provides specialized methods for space-mapping and expansion. 

*   **Infinite CullRect:** Represented internally via `gfx::Rect(LayoutRect::InfiniteIntRect())`. Used when culling is explicitly disabled or mathematically impossible (e.g., degenerate matrices, certain SVG filters, or small content sizes where the overhead of culling exceeds painting).
*   **Coordinate Space:** A `CullRect` is always defined in the **local transform space** of the current `TransformPaintPropertyNode` being processed.

---

### 3. PIPELINE PHASE 1: CULL RECT UPDATING (`CullRectUpdater`)
Prior to the `PrePaint` phase, `CullRectUpdater` walks the `LayoutObject` and Paint Property trees to compute the `CullRect` for every `FragmentData`.

#### 3.1. Initialization
The root `FrameView` initializes the root `CullRect` strictly to the layout viewport's visible rect.

#### 3.2. Propagation and Expansion (`ApplyPaintProperties`)
As the updater traverses down the tree, the `CullRect` must be mapped from the parent's transform space to the child's transform space using `GeometryMapper`.

1.  **Scroll Translation & Expansion:**
    When crossing a scroll boundary (a `ScrollPaintPropertyNode`), the `CullRect` is clipped to the scroll container's overflow clip rect. If the scroller is composited, the `CullRect` is expanded in the scrollable directions to prevent checkerboarding during asynchronous compositor scrolling.
    *   *Expansion Metric:* Typically **4000 CSS pixels** (adjusted by `LocalFrameView::GetCullRectExpansionFactor()`, scaled by Device Pixel Ratio).
    *   *Optimization:* If the total scrollable area is smaller than the expanded rect, the `CullRect` simply encompasses the entire scrollable overflow rect.
2.  **Coordinate Space Mapping:**
    `GeometryMapper::LocalToAncestorVisualRect` and its inverse `AncestorToLocalVisualRect` are used. The parent's `CullRect` is mapped into the child's local space via `GeometryMapper::SourceToDestinationRect()`.
3.  **3D & Perspective Transforms:**
    If a transform matrix is non-invertible, 3D-degenerate, or contains complex perspective projections that project behind the camera ($w \le 0$), `CullRect` defaults to `Infinite()` or `Empty()` depending on visibility determinants.
4.  **Clips (`ClipPaintPropertyNode`):**
    Any intermediate CSS `clip`, `overflow: hidden`, or `clip-path` is mapped to the current space and intersected (`gfx::Rect::Intersect`) with the active `CullRect`.

---

### 4. PIPELINE PHASE 2: INTERSECTION & GEOMETRY CULLING (`PaintLayerPainter` & `NGBoxFragmentPainter`)
During the `Paint` phase, Blink traverses the `NGPhysicalFragment` tree. Culling occurs at two granularities: **Subtree Culling** and **Box/Fragment Culling**.

#### 4.1. The Intersection Test (`Intersects`)
The fundamental culling check is `CullRect::Intersects(const gfx::Rect& bounding_box)`. 
```cpp
bool CullRect::Intersects(const gfx::Rect& rect) const {
  if (IsInfinite())
    return true;
  return rect.Intersects(rect_);
}
```
*Note: For subpixel layout (`PhysicalRect`), the geometry is first snapped or enclosed (`ToEnclosingRect(physical_rect)`) to convert from `LayoutUnit` (1/64th pixel) to `gfx::Rect` (integer) before intersection, ensuring conservative bounds (no false-positive culling).*

#### 4.2. PaintLayer Culling (Subtree Level)
In `PaintLayerPainter::Paint()`, before descending into a `PaintLayer`:
1.  The layer’s **Physical Bounding Box** (including visual overflow from shadows, outlines, and descendants) is retrieved.
2.  The painter checks if the layer has a local `CullRect` (stored on `FragmentData`).
3.  If `cull_rect.Intersects(layer_bounds)` returns `false`, the entire `PaintLayer` and its subtree (unless a descendant escapes the clip/transform tree) are skipped.

#### 4.3. Fragment & Inline Culling (Leaf Level)
Inside `NGBoxFragmentPainter`:
1.  **Block-level Culling:** Before painting backgrounds, borders, or children of a block fragment, `IntersectsVisualRect()` is called against the fragment's `InkOverflow` rect (offset by the current paint offset).
2.  **Inline/Text Culling (`NGInlineBoxFragmentPainter`):** For massive blocks of text, Blink iterates through `NGInlineCursor`. Line boxes (`kLineBox`) have their physical rects checked against the `CullRect`. If a line box does not intersect, the cursor calls `MoveToNextSkippingChildren()`, bypassing all `kText` and `kAtomicInline` fragments on that line.

---

### 5. SPECIAL CASES & AUDIT VULNERABILITIES

#### 5.1. Pixel-Moving Filters (`EffectPaintPropertyNode`)
If an element or ancestor has a CSS `filter` (e.g., `blur()`, `drop-shadow()`) or `backdrop-filter`, a geometry outside the `CullRect` might cast pixels *into* the `CullRect`.
*   **Mitigation:** During `CullRectUpdater`, when passing through a pixel-moving `EffectPaintPropertyNode`, the `CullRect` is expanded in the local space by the inverse of the filter's outsets (`FilterOperations::MapRect()`).

#### 5.2. Fragmentation (Multi-column / Printing)
In fragmented flows, a single `LayoutObject` generates multiple `FragmentData` entries. Each fragment has its own `PaintProperties` and its own localized `CullRect`. Intersection tests are strictly bound to the current `FragmentData` context passed via `PaintInfo`.

#### 5.3. Out-of-Flow Positioned Descendants
A child might not intersect the `CullRect`, so its painting is skipped. However, it may contain an `absolute` or `fixed` positioned descendant that *does* intersect the viewport.
*   **Mitigation:** Blink separates self-painting layers (`PaintLayer`) and utilizes flags like `DescendantMayHaveTransformRelatedOperations()` and `HasSelfPaintingLayerDescendant()`. `NGBoxFragmentPainter` will only cull the *entire* subtree if `PhysicalFragment::HasFloatingDescendantsForPaint()` and out-of-flow flags guarantee all children are geometrically contained within the parent's overflow rect.

#### 5.4. CullRect Invalidation (`PaintInvalidator`)
When the user scrolls beyond a specific threshold, the cached `DisplayItemList` lacks the geometry that is about to enter the viewport.
*   **Mechanism:** `CullRectUpdater::ProactivelyUpdate()` checks if the new scroll offset brings the viewport edge within **512 pixels** (the minimum scroll delta threshold) of the existing `CullRect` boundary.
*   If breached, a new `CullRect` is calculated. `PaintController` invalidates the affected `DisplayItemClient`s, forcing a repaint of the newly exposed regions during the next lifecycle update (`DocumentLifecycle::kInPaint`).

---

### 6. CONCLUSION
Blink's `CullRect` intersection architecture relies on conservative `gfx::Rect` bounding-box approximations mapped across the `TransformPaintPropertyNode` graph. By coupling `GeometryMapper` conversions with a 4000px composited-scroll expansion heuristic, Blink successfully culls out-of-view DOM subtrees and inline boxes on the main thread, preventing `cc::DisplayItemList` bloat while maintaining low checkerboard rates on the compositor thread. 

**STATUS:** AUDIT COMPLETE. NO ANOMALIES DETECTED IN CORE LOGIC.