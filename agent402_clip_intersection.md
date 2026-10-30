**Agent 402 reporting.** Initiating audit of the Blink Compositor (`cc`) clip intersection subsystem, focusing on 2D Axis-Aligned Bounding Box (AABB) intersection primitives.

In the Blink/Chromium compositor, 2D bounding box intersections are the foundational operations for constructing the **Clip Tree** (part of the Property Trees), determining layer visibility, culling draw quads, and calculating damage rects. These operations are primarily handled within the `gfx` geometry library (`ui/gfx/geometry/`), specifically utilizing `gfx::Rect` (integer) and `gfx::RectF` (floating-point).

Below is the technical breakdown of the 2D bounding box intersection logic, transformation handling, and edge-case protocols.

---

### 1. Data Representation
Unlike standard graphics APIs that may use `(min_x, min_y, max_x, max_y)`, Chromium’s `gfx::Rect` and `gfx::RectF` are defined by **Origin and Size**:
*   **Origin:** $(x, y)$
*   **Dimensions:** $(width, height)$
*   **Implicit Max Bounds:** $right = x + width$, $bottom = y + height$

---

### 2. Core Intersection Algorithm (`gfx::Rect::Intersect`)
When the compositor intersects two clips in the same coordinate space (e.g., a child clip node with its parent clip node), it computes the overlapping region of Rectangle $A$ and Rectangle $B$.

#### Mathematical Formulation
1.  **Compute the new top-left origin $(rx, ry)$:**
    $$rx = \max(A.x, B.x)$$
    $$ry = \max(A.y, B.y)$$

2.  **Compute the new bottom-right extent $(rr, rb)$:**
    $$rr = \min(A.x + A.width, B.x + B.width)$$
    $$rb = \min(A.y + A.height, B.y + B.height)$$

3.  **Validate Intersection (Non-Empty Check):**
    If $rx \ge rr$ or $ry \ge rb$, the rectangles do not intersect (or the intersection is degenerate).
    *   **Action:** The compositor zeroes out the rect to $(0, 0, 0, 0)$ to maintain a canonical representation of an empty clip.

4.  **Finalize Dimensions:**
    $$width = rr - rx$$
    $$height = rb - ry$$

---

### 3. Compositor Coordinate Space & `gfx::MathUtil`
Clips rarely exist in the exact same coordinate space. Before a 2D intersection can occur in `cc::ClipTree`, the bounding boxes must be projected into a common target space (usually the target Render Surface space or Screen Space).

1.  **2D Axis-Aligned Transforms:** If the `TransformNode` between the two clips only contains 2D translation and/or scale, the `gfx::RectF` is simply scaled and offset, remaining an AABB. Standard `Intersect()` is then applied.
2.  **Non-Axis-Aligned / 3D Transforms:** If a layer is rotated or skewed, its local clip rect becomes a **Quad** (`gfx::QuadF`) in the target space. 
    *   To maintain performance during tree walks, the compositor often approximates this by taking the **Bounding Box of the mapped Quad** (`cc::MathUtil::MapClippedRect` or `MapEnclosingClippedRect`).
    *   *Audit Note:* If exact clipping is required for a rotated clip, the compositor cannot use simple 2D AABB intersection; it must generate a `RenderPass` with a stencil buffer or apply AA shader clipping (`cc::DrawQuad`).

---

### 4. Integer Snapping and Conservative Rounding
The compositor calculates clips in floating-point (`gfx::RectF`), but pixel buffers, damage rects, and scissor rects require integers (`gfx::Rect`). Converting between them during intersection is a high-risk area for visual artifacts (seams) or over-invalidation.

*   **`gfx::ToEnclosingRect(RectF)` (Outset):** 
    Uses `std::floor` for $(x, y)$ and `std::ceil` for $(right, bottom)$. 
    *   *Usage:* **Damage calculations and Culling.** Ensures no partially covered pixels are accidentally clipped out.
*   **`gfx::ToEnclosedRect(RectF)` (Inset):** 
    Uses `std::ceil` for $(x, y)$ and `std::floor` for $(right, bottom)$. 
    *   *Usage:* **Opaque region tracking.** When determining if a layer completely occludes another (`cc::OcclusionTracker`), the compositor must be 100% certain a pixel is fully covered before culling the geometry behind it.

---

### 5. Security & Stability Audit Vectors (Edge Cases)
As Agent 402, my audit of the `cc` and `gfx` intersection pipelines highlights three critical failure modes that Chromium explicitly defends against:

1.  **Integer Overflow (`base::ClampedNumeric`):**
    Computing $x + width$ in `gfx::Rect` can overflow a 32-bit signed integer (`INT_MAX`) when dealing with massive CSS values (e.g., `10000000px`). Chromium uses `base::ClampAdd` to saturate at `std::numeric_limits<int>::max()` rather than wrapping around to negative values, which would corrupt the clip tree and potentially cause out-of-bounds rasterization.
2.  **Floating-Point `NaN` and `Infinity`:**
    During `MapClippedRect`, a singular matrix or extreme perspective transform ($w \le 0$) can produce `NaN` or `Inf`. If `NaN` enters `std::max` or `std::min`, the condition $rx \ge rr$ may evaluate falsely, bypassing emptiness checks. `cc::MathUtil` clamps homogeneous coordinates ($w > 0$) before projection to prevent invalid floats from entering `gfx::RectF::Intersect`.
3.  **Accumulated Precision Loss:**
    In deep `ClipTree` hierarchies (`cc::draw_property_utils::ComputeClips`), intersecting a rect, transforming it, and intersecting it again can cause floating-point drift. This results in "1-pixel bleed" at the edges of `overflow: hidden` containers. The compositor mitigates this by retaining clips in their local space where possible and accumulating the transforms before doing a single projection into target space.

**Audit Status:** Nominal. AABB intersection primitives are bounded and overflow-safe. Ready for next directive.