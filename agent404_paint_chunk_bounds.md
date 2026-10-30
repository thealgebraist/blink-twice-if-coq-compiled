**AUDIT LOG: AGENT 404**
**SUBSYSTEM:** Chromium / Blink Rendering Engine (`platform/graphics/paint`)
**TARGET:** `PaintChunk` Visual Rect Bounding & Union Coverage
**STATUS:** ACTIVE AUDIT

---

### 1. Executive Summary: `PaintChunk` Bounding
In the Blink Paint Artifact pipeline (CompositeAfterPaint), a `PaintChunk` represents a contiguous sequence of `DisplayItem`s that share an identical `PropertyTreeState` (Transform, Clip, Effect, Scroll). 

The `PaintChunk::bounds` (and the raster invalidation `visual_rect`) must represent the **conservative, axis-aligned bounding box (AABB)** of all contained `DisplayItem`s within the local transform space of that chunk.

### 2. The Union Mechanism (`gfx::Rect::Union`)
The chunk’s bounding box is computed iteratively during the `PaintController` commit phase via the `PaintChunker`. 

For a chunk $C$ containing display items $D_1, D_2, \dots, D_n$, the chunk bounds $B(C)$ is defined as:

$$B(C) = \bigcup_{i=1}^{n} \text{VisualRect}(D_i)$$

#### Implementation Mechanics:
1. **Initialization:** When a new `PaintChunk` is initialized by the `PaintChunker`, its `bounds` is set to the `visual_rect` of the first `DisplayItem` appended to it.
2. **Accumulation:** For every subsequent `DisplayItem` sharing the same `PropertyTreeState`, the chunk expands its coverage using `gfx::Rect::Union` (or `gfx::RectF::Union` before integer snapping).
3. **Empty Rect Handling:** Standard `gfx::Rect::Union` logic applies—if $D_i$ has an empty visual rect (width $\le 0$ or height $\le 0$), it is ignored in the union calculation to prevent origin $(0,0)$ skewing. If all items are empty, the chunk bounds remain empty at the location of the first item.

### 3. Coordinate Space & Coverage Constraints
Agent 404 notes that a simple geometric union is insufficient without strict adherence to coordinate space rules:

* **Local Transform Space:** The union happens strictly in the **local transform space** of the `PaintChunk`'s `PropertyTreeState`. Items are *not* mapped to screen space prior to chunk unioning.
* **Outset Coverage:** `DisplayItem` visual rects must already include paint outsets (e.g., `box-shadow`, `outline`, glyph overhangs, anti-aliasing fringes) *before* being unioned into the `PaintChunk`.
* **Enclosing Int Rects:** Because `DisplayItem` geometry often originates as subpixel `LayoutRect` or `gfx::RectF`, the visual rect is converted via `gfx::ToEnclosingRect()` prior to or during chunk bounds aggregation. This guarantees conservative coverage (rounding outward) to prevent subpixel clipping during rasterization.

### 4. Edge Cases & Audit Vulnerabilities
During the audit of union bounding box coverage, the following vectors are flagged as high-risk for under-invalidation or clipping artifacts:

#### A. Pixel-Moving Filters (`cc::FilterOperations`)
If a `PaintChunk` is associated with an `EffectPaintPropertyNode` containing a pixel-moving filter (e.g., `blur()`, `drop-shadow()`), the raw union of the `DisplayItem`s is **insufficient**. 
* **Mitigation:** The `PaintChunk` bounds (or the subsequent `cc::Layer` bounds mapped via `GeometryMapper`) must be expanded using `FilterOperations::MapRect()`.

#### B. Infinite / Unbounded DisplayItems
Certain drawing operations (e.g., `SkCanvas::drawPaint` or infinite background fills) do not have intrinsic geometry.
* **Mitigation:** These items must be bounded by the current `ClipPaintPropertyNode` within the `PropertyTreeState` before being fed into the chunk union, otherwise `gfx::Rect` overflow occurs (clamping to `INT_MAX`, causing massive tile memory allocation in `cc`).

#### C. Subsequence Caching & Hit Testing
`PaintChunk` bounds are not solely unioned from drawing items (`DrawingDisplayItem`). They must also union:
* `ForeignLayerDisplayItem` bounds.
* `HitTestData` rects (e.g., transparent touch-action regions or scroll hit test rects).
* `RegionCaptureData` / `LayerSelection` bounds.
* *Audit Note:* `PaintChunk::bounds` is the union of `drawable_bounds` AND non-drawing metadata rects. `drawable_bounds` is tracked separately as a strict subset to optimize `cc::PictureLayer` tile generation (ignoring empty hit-test areas for raster).

### 5. Downstream Consumption (`GeometryMapper`)
Once the `PaintChunk` union is finalized, its coverage is audited against `GeometryMapper::LocalToAncestorVisualRect()`. 
1. The chunk's `bounds` are mapped from the chunk's local state to the target `cc::Layer` state.
2. Clips between the chunk state and layer state are applied (`Intersect`).
3. Transforms are applied, and the resulting quad is wrapped in a new AABB (`EnclosingRect`).

**AUDIT CONCLUSION:** 
Union bounding box coverage in `PaintChunk` is mathematically conservative. Under-coverage bugs rarely stem from `gfx::Rect::Union` itself, but rather from upstream `DisplayItem`s under-reporting their ink overflow (`VisualRect`) or downstream failures to expand the unioned box for backdrop-filters/pixel-moving effects. 

**AGENT 404 — END REPORT.**