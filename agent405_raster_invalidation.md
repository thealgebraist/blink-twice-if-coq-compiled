**AUDIT REPORT: Blink Raster Invalidation & Compositor Damage Rect Containment**
**Auditor:** Agent 405
**Target Subsystem:** Chromium Blink Paint Controller (`blink::PaintController`), Paint Artifact Compositor (`blink::PaintArtifactCompositor`), and Compositor Frame Generation (`cc::DamageTracker`).

---

### 1. Executive Summary
Damage rect containment is the mechanism by which Blink restricts the geometric bounds of visual updates (invalidations) to minimize the pixel area re-rasterized by GPU/CPU workers and re-drawn by the display compositor (`viz`). 

Improper containment results in **over-invalidation** (wasting GPU rasterization cycles and memory bandwidth) or **under-invalidation** (visual artifacts/stale pixels). This audit details the end-to-end pipeline of damage rect generation, coordinate space mapping, clipping, and unionization under the current ** CompositeAfterPaint (CAP)** architecture.

---

### 2. Phase I: Generation of Raster Invalidations (Blink)
In Blink, layout objects do not directly emit damage rects to the compositor. Instead, during the **PrePaint** lifecycle phase, changes to the DOM/Layout tree are translated into property tree changes or display item invalidations.

During the **Paint** lifecycle phase, `PaintController` generates a `PaintArtifact` (a list of `DisplayItem`s and a list of `PaintChunk`s). 

#### The Role of `RasterInvalidator`
For each composited layer (`cc::PictureLayer`), `RasterInvalidator::Generate()` compares the new `PaintChunk`s against the `PaintChunk`s from the previous frame.
1. **Chunk Matching:** It attempts to match chunks by ID.
2. **Bounds & Property Comparison:** If a chunk's bounds change, its `DisplayItem`s are invalidated, or its associated Paint Property Tree nodes (`TransformPaintPropertyNode`, `ClipPaintPropertyNode`, `EffectPaintPropertyNode`) mutate, an invalidation rect is generated.
3. **Subpixel Accumulation:** Bounds are expanded to ` gfx::Rect` (integer coordinates) using `EnclosingIntRect` to account for subpixel antialiasing bleed.

---

### 3. Phase II: Containment via Property Trees (`GeometryMapper`)
Before an invalidation rect can be recorded on a `cc::Layer`, it must be mapped from the local coordinate space of the `PaintChunk` to the coordinate space of the backing composited layer. **This is the primary locus of geometric containment.**

`GeometryMapper::LocalToAncestorVisualRect()` is invoked to project the chunk's visual rect up the property trees to the layer's property tree state:

1. **Clip Containment (`ClipPaintPropertyNode`):** 
   As the rect traverses up the Clip Tree, it is intersected (`gfx::RectF::Intersect`) with every intermediate clip node (e.g., `overflow: hidden`, CSS `clip-path`). If an intersection results in an empty rect (`IsEmpty()`), the invalidation is culled entirely.
2. **Transform Application (`TransformPaintPropertyNode`):**
   The clipped rect is mapped through 2D/3D transformation matrices. 3D perspective projections or rotations require taking the axis-aligned bounding box (`AABB`) of the transformed quad, which *expands* the damage rect (containment loss due to axis alignment).
3. **Effect Expansion (`EffectPaintPropertyNode`):**
   Certain effects *break* containment by expanding the visual rect. For example, a `blur()` filter or `drop-shadow` requires calling `MapRect()` on the `FilterOperations`, which outsets the damage rect to cover the blur kernel's radius.

---

### 4. Phase III: Layer-Level Aggregation (`cc::PictureLayer`)
Once `RasterInvalidator` maps the chunk's invalidation rect into the layer's space, it passes the rect to `cc::PictureLayer::SetNeedsDisplayRect(const gfx::Rect& dirty_rect)`.

#### `cc::Region` vs. `gfx::Rect`
Within `cc::Layer`, invalidations are accumulated into an `update_rect_` (a single `gfx::Rect`). 
* **Containment Vulnerability (Bounding Box Bloat):** If a layer has two 10x10px invalidations at opposite corners of a 1920x1080px layer, `SetNeedsDisplayRect` performs a `gfx::Rect::Union()`. The resulting `update_rect_` becomes the entire 1920x1080px area.
* **Mitigation (Tile-Based Containment):** During the `Commit` phase, `PictureLayerImpl` intersects this massive `update_rect_` with its `PictureLayerTiling` grid. Only tiles that intersect the `RasterSource` invalidation region are marked dirty. However, within `RasterInvalidator`, tracking is done via `cc::Region` (a SkRegion wrapper using run-length encoded rectangles) up until it is handed off to the tile manager, preventing the union-bloat from triggering unnecessary tile rasterization in the middle of the two corners.

---

### 5. Phase IV: Compositor Frame Damage (`cc::DamageTracker`)
After rasterization, the Compositor Thread (impl-side) prepares a `viz::CompositorFrame` to send to the Display Compositor. `cc::DamageTracker` calculates the final **Surface Damage Rect** for each `cc::RenderSurfaceImpl`.

1. **Layer Damage Accumulation:**
   `DamageTracker` iterates over all `LayerImpl`s contributing to a target `RenderSurfaceImpl`. It takes each layer's `update_rect()`, transforms it into the target surface's space via `cc::MathUtil::MapEnclosingClippedRect()`, and clips it against the layer's `clip_rect()`.
2. **`cc::DamageAccumulator`:**
   Rather than a simple `gfx::Rect`, `DamageTracker` uses an internal accumulator that attempts to maintain a bounded complexity region before collapsing into a single bounding box.
3. **Surface-Level Containment:**
   The accumulated damage is strictly intersected with the `RenderSurfaceImpl`'s `content_rect()`. Damage cannot escape a RenderSurface unless that surface itself has pixel-moving filters applied by its parent surface.
4. **Root Damage Rect:**
   The damage rect of the root `RenderSurfaceImpl` becomes the `root_damage_rect` of the `CompositorFrame`. This is passed to the OS/GPU driver via `glSwapBuffersWithDamageKHR` (or platform equivalent) for **Partial Swap**, physically restricting the display controller from refreshing untouched screen pixels.

---

### 6. Audit Findings: Containment Failure Modes (Edge Cases)

As Agent 405, I flag the following scenarios where damage rect containment degrades in production:

1. **Layer Squashing Sprawl:**
   In CAP, multiple non-overlapping DOM elements may be squashed into a single `cc::PictureLayer` to save memory. If one small element moves, the squashed layer's overall bounds may shift. If the layer bounds origin shifts, the *entire* layer's coordinate space is invalidated, causing a full-layer raster invalidation.
2. **Complex CSS Filters (`feDisplacementMap`, `blur`):**
   If a small damage rect intersects an element with a backdrop-filter or a large blur radius, `DamageTracker::ExpandDamageInsideRectWithFilters()` must expand the damage rect significantly. Any change *underneath* a `backdrop-filter` forces a re-read and re-draw of the entire filtered bounds.
3. **Scroll Anchoring & Cull Rect Changes:**
   Infinite scrollers update their `CullRect` (the rect used by Blink to avoid painting offscreen content) periodically. When the `CullRect` shifts, `RasterInvalidator` sees "new" `PaintChunk`s appearing at the leading edge and disappearing at the trailing edge, generating massive strip invalidations, which must be carefully contained so they do not unionize across the viewport center.

---

### 7. Diagnostic Verification (Telemetry & Tooling)
To verify damage rect containment on a live target:
* **Run Flag:** `--show-paint-rects` (visualizes Blink-side raster invalidations in red).
* **Run Flag:** `--show-surface-damage-rects` (visualizes `cc::DamageTracker` output in orange).
* **Tracing:** Record a `chrome://tracing` profile with categories `blink.invalidation`, `cc`, and `disabled-by-default-blink.debug.layout.trees`. Inspect `PaintController::FinishCycle` for `RasterInvalidationTracking` JSON payloads to verify exact chunk-to-rect mappings.

**Audit Status:** COMPLETE. Pipeline architecture verified against Chromium trunk specifications.