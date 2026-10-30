**[AUDIT LOG: AGENT 412]**
**Target:** Chromium Blink / `cc` (Chrome Compositor)
**Subject:** Viewport Tiling Coverage & Eviction Hierarchy
**Status:** ACTIVE AUDIT

---

### 1. Executive Summary
The Blink Compositor (`cc`) does not rasterize entire scrolling layers at once. Instead, it divides `PictureLayerImpl` instances into discrete spatial grids (`TilingData`) managed by a `PictureLayerTilingSet`. To balance memory constraints against visual "checkerboarding" (unrasterized content entering the viewport during high-velocity scroll or pinch-zoom), the compositor categorizes tiles into concentric **Coverage Rects** with strictly ordered rasterization and eviction priorities.

---

### 2. The Coverage Hierarchy (Concentric Rects)
For every active `PictureLayerTiling`, the compositor computes four primary geometric bounds within the layer's content space. From innermost (highest priority) to outermost (lowest priority):

#### A. `visible_rect` (The Viewport)
*   **Definition:** The exact mathematical intersection of the device viewport (or ancestor clip rect) and the layer’s bounds, mapped into target content space.
*   **Priority:** `NOW` (`TilePriority::NOW`).
*   **Audit Note:** Any missing tile in this rect results in immediate visual degradation (checkerboarding). The `TileManager` routes these directly to the top of the raster worker pool queues. If a tile is required for Activation (Pending Tree $\rightarrow$ Active Tree), it blocks tree activation until rasterized.

#### B. `skewport_rect` (Velocity-Predicted Viewport)
*   **Definition:** An asymmetrical expansion of the `visible_rect` projected along the current scroll velocity vector ($\vec{v}$).
*   **Formula:** Calculated using historical scroll deltas over frames and the `skewport_target_time_in_seconds` parameter.
*   **Priority:** `SOON` (`TilePriority::SOON`).
*   **Audit Note:** Critical for high-velocity fling gestures. Tiles inside the skewport are prioritized by their distance to the `visible_rect` along the velocity vector.

#### C. `soon_border_rect` (Omnidirectional Buffer)
*   **Definition:** A uniform padding around the `visible_rect` (typically a fixed pixel margin or percentage of viewport dimensions).
*   **Priority:** `SOON` (`TilePriority::SOON`).
*   **Audit Note:** Guards against erratic changes in scroll direction or sudden micro-scrolls where the `skewport_rect` has not yet projected coverage.

#### D. `eventually_rect` (The Pre-paint & Retention Boundary)
*   **Definition:** A massive bounding box encompassing the viewport, usually constrained by a total pixel area budget (e.g., `tiling_interest_area_padding`, often ~3000-4000 pixels out from the viewport depending on device RAM).
*   **Priority:** `EVENTUALLY` (`TilePriority::EVENTUALLY`).
*   **Audit Note:** Defines the absolute outer boundary of existence for tiles. 
    *   *Inward transition:* Tiles entering this rect are instantiated and queued for background raster.
    *   *Outward transition:* Tiles falling outside the `eventually_rect` are immediately culled from the tiling grid and their GPU memory is reclaimed.

---

### 3. Multi-Resolution Tiling Coverage (`PictureLayerTilingSet`)
A layer does not rely on a single grid. During pinch-zoom or CSS scale animations, `PictureLayerTilingSet` maintains multiple `PictureLayerTiling` instances at varying contents scales.

*   **High-Resolution (`HIGH_RESOLUTION`):** The ideal scale matching the current `device_scale_factor` $\times$ `page_scale_factor`. This is the primary target for `NOW` coverage.
*   **Low-Resolution (`LOW_RESOLUTION`):** Typically scaled down by a factor of 4 (1/16th the pixel area). Used as a rapid-raster fallback during fast scrolls on non-LCD-text layers to prevent full checkerboarding when the `HIGH_RESOLUTION` raster threads fall behind.
*   **Non-Ideal Resolutions (`ABOVE`/`BELOW`):** Leftover tilings from previous zoom levels. Retained temporarily by the compositor to provide coverage until the newly targeted `HIGH_RESOLUTION` tiling finishes rasterizing its `visible_rect`.

---

### 4. Coverage Iteration & Tile Resolution
When the compositor prepares a `CompositorFrame` (specifically during `PictureLayerImpl::AppendQuads`), it executes the **Coverage Iterator** (`PictureLayerTilingSet::CoverageIterator`).

**The Resolution Algorithm:**
1. The iterator steps through the `visible_rect` of the layer.
2. It attempts to fetch a `READY_TO_DRAW` tile from the **Ideal (`HIGH_RESOLUTION`) Tiling**.
3. **Fallback 1:** If the ideal tile is missing/unrasterized, it queries **Non-Ideal Tilings** (closest scale to ideal first) that cover that specific sub-rect.
4. **Fallback 2:** If still uncovered, it falls back to the **`LOW_RESOLUTION` Tiling**.
5. **Failure State:** If no tiling has a ready resource for that sub-rect, the compositor emits a `SolidColorDrawQuad` (background color) or `CheckerboardDrawQuad`, and flags the frame as having incomplete tile coverage.

---

### 5. Dual-Tree Synchronization (Pending vs. Active)
Coverage is evaluated across both compositor trees simultaneously via `CombinedTilePriority`:
*   **Active Tree:** Represents what is currently on screen. Highest priority for `NOW` tiles to fix immediate checkerboarding.
*   **Pending Tree:** Represents the incoming commit from the Blink main thread. `NOW` tiles on the pending tree are flagged `REQUIRED_FOR_ACTIVATION`. The `TileManager` interleaves Active `NOW` and Pending `NOW` tiles depending on the current `TreePriority` mode:
    *   `SAME_PRIORITY_FOR_BOTH_TREES` (Default)
    *   `SMOOTHNESS_TAKES_PRIORITY` (Prioritizes Active tree coverage; starves Pending tree during active scrolling).
    *   `NEW_CONTENT_TAKES_PRIORITY` (Prioritizes Pending tree coverage to resolve main-thread updates).

---

### 6. Audit Diagnostics & Anomalies
As Agent 412, when auditing trace logs (`cc.debug`, `disabled-by-default-cc.debug.picture`), watch for the following coverage failure modes:

1.  **Interest Area Thrashing:** If the `eventually_rect` is sized too small relative to GPU memory limits, tiles are evicted and re-rasterized repeatedly during bi-directional scrolling.
2.  **Skewport Starvation:** If raster tasks take longer than the frame budget (e.g., complex SVG filters or heavy image decoding), the `visible_rect` will overtake the `skewport_rect`, collapsing `SOON` priority directly into `NOW` and causing visible stutter/checkerboarding.
3.  **Scale Proliferation:** Unbounded pinch-zoom gestures generating too many discrete `PictureLayerTiling` scales, fragmenting the `TileManager` memory budget and starving the `HIGH_RESOLUTION` `visible_rect` of GPU resources (mitigated by snapping scales and aggressive eviction of non-ideal tilings).

**[END OF AUDIT REPORT - AGENT 412]**