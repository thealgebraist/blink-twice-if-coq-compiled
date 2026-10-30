**[SYSTEM INITIALIZATION: AGENT 413 - AUDIT PROTOCOL ACTIVE]**
**Target Architecture:** Chromium / Blink Rendering Engine (Compositor & Paint Pipelines)
**Subject:** Occlusion Culling Soundness – Opacity Preservation Verification

---

### 1. EXECUTIVE SUMMARY
In the Blink rendering engine (specifically within the `cc` compositor layer and the Blink `PaintChunk` to `cc::Layer` translation phase), **Occlusion Culling** is an optimization that prevents the rasterization and drawing of quads/layers completely hidden behind other opaque elements. 

**Opacity Preservation** is the strictest invariant of this system: *A layer or quad must never be designated as an "occluder" if its effective alpha is less than `1.0` (255), and a partially transparent layer must never be fully culled unless occluded by a verified fully opaque region.* Violating this invariant results in missing content, unrendered backgrounds, or Hall-of-Mirrors (HOM) artifacts.

---

### 2. THE SOUNDNESS INVARIANT
For an element $A$ to occlude an element $B$ within screen-space region $R$:
1. $\text{Depth}(A) > \text{Depth}(B)$ (in draw order).
2. $\text{Bounds}(A) \cap R = R$.
3. **$\text{Opaque}(A, R) = \text{True}$.**

Agent 413 verifies that condition (3) holds across the three main stages of the pipeline: **Blink Paint**, **Property Trees**, and **Compositor Frame Generation (`cc::OcclusionTracker`)**.

---

### 3. ARCHITECTURAL AUDIT: OPACITY PRESERVATION MECHANISMS

#### A. Blink Paint Phase & `ContentsOpaque` Propagation
During the PrePaint and Paint phases, Blink computes whether a `PaintChunk` is known to be entirely opaque.
*   **Audit Point:** ` PaintChunk::known_to_be_opaque`
*   **Mechanism:** Blink evaluates CSS properties (`background-color`, `opacity`, `mix-blend-mode`, `filter`, `mask-image`, etc.). If `background-color` has an alpha of `1.0` and fills the layout rect, the chunk is flagged as opaque.
*   **Soundness Check:** If an image resource (`<img>` or `background-image`) is used, Blink queries the decoded `SkBitmap::isOpaque()` flag. Until the image is decoded, or if it contains an alpha channel (e.g., PNG32, WebP with alpha), `known_to_be_opaque` **must** default to `false`.

#### B. Compositor Property Trees (`cc::EffectTree`)
Blink no longer uses a traditional layer tree to calculate hierarchy; it uses Property Trees (Transform, Clip, Effect, Scroll). Opacity is governed by the `cc::EffectNode`.
*   **Audit Point:** `EffectNode::opacity` and `EffectNode::screen_space_opacity`
*   **Mechanism:** Opacity is multiplicative. A layer might have `contents_opaque = true` locally (e.g., a solid `#FF0000` div), but if an ancestor `EffectNode` has `opacity: 0.99`, the *effective* opacity drops below `1.0`.
*   **Soundness Check:** The `OcclusionTracker` queries the `EffectTree` before allowing a layer to write to the occlusion buffer. If `EffectNode::screen_space_opacity != 1.0f`, the layer's contribution to the `SimpleEnclosedRegion` (the occlusion mask) is completely discarded.

#### C. `cc::OcclusionTracker` & `SimpleEnclosedRegion`
During the `DrawLayers` phase in the compositor, the `OcclusionTracker` iterates through layers **front-to-back** (reverse draw order).
*   **Audit Point:** `OcclusionTracker::MarkOccludedBehindLayer()`
*   **Mechanism:** As it traverses, it accumulates a `cc::SimpleEnclosedRegion` (an approximation of complex geometry into a set of largest-possible Axis-Aligned Bounding Boxes [AABBs]) representing the opaque screen space.
*   **Soundness Check (Transformations):** If a `contents_opaque` layer undergoes a non-axis-aligned transformation (e.g., `transform: rotate(45deg)` or a 3D perspective), its edges undergo **anti-aliasing (AA)**. AA introduces fractional opacity at the boundary pixels.
    *   *Preservation Enforcement:* When mapping the layer's `visible_layer_rect` to screen space via `MathUtil::MapEnclosedRectWith2dAxisAlignedTransform`, the engine **shrinks** (insets) the opaque rect to exclude anti-aliased edges, or drops the occlusion contribution entirely if an inscribed AABB cannot be safely calculated.

#### D. Viz & `viz::DrawQuad` Level Culling
Before submitting the `CompositorFrame` to the GPU process (Viz), layers are broken down into `DrawQuad`s.
*   **Audit Point:** `viz::SharedQuadState::are_contents_opaque` & `viz::DrawQuad::needs_blending`
*   **Mechanism:** A quad is split into visible and occluded regions. If a quad is only *partially* occluded by an opaque region in front of it, the `OcclusionTracker` shrinks the `DrawQuad::visible_rect`.
*   **Soundness Check:** If `needs_blending` is `true` on the occluding quad, it cannot shrink the `visible_rect` of quads behind it. Furthermore, for `TileDrawQuad` (rasterized tiles), if a tile sits on the edge of a layer and requires AA, `needs_blending` is forced to `true`, neutralizing its ability to occlude background quads at that edge.

---

### 4. EDGE CASES & VULNERABILITY VECTORS (AUDIT FOCUS)

Agent 413 flags the following vectors where Opacity Preservation is historically prone to regression:

1.  **Subpixel Positioning & Fractional Scales:**
    *   *Risk:* A `contents_opaque` layer placed at `x: 10.5px` will be rasterized with blended edges.
    *   *Mitigation:* `LayerImpl::opaque_rect()` is snapped inward using `gfx::ToEnclosedRect()`, ensuring fractional pixels at the perimeter are excluded from the occlusion mask.
2.  **CSS `backdrop-filter` and Blend Modes:**
    *   *Risk:* If Layer A (Opaque) is in front of Layer B (Has `backdrop-filter: blur()`), Layer A occludes B. However, B needs to read the pixels of Layer C (behind B) to compute the blur, which might bleed *out* from behind Layer A's bounds.
    *   *Mitigation:* Occlusion culling must expand the required `visible_rect` of layers behind a backdrop-filter by the filter's pixel-movement radius (kernel size), preventing premature culling of pixels that affect the visible fringe.
3.  **Rounded Corners (`border-radius`) & Clip Paths:**
    *   *Risk:* A `div` has a solid background (`contents_opaque = true`), but also `border-radius: 10px`. The corners are transparent!
    *   *Mitigation:* When `EffectNode` or `ClipNode` applies a `gfx::RRectF` (Rounded Rect) mask, the `OcclusionTracker` intersects the opaque region with the **inscribed rectangle** of the `RRectF`, never the bounding box.
4.  **Color Space & HDR:**
    *   *Risk:* Out-of-gamut colors or floating-point framebuffers where alpha values might exceed `1.0` or suffer from floating-point inaccuracy (`0.9999999f`).
    *   *Mitigation:* Strict `float` equality checks (`opacity == 1.0f`) are used rather than epsilon comparisons, failing *safe* (assuming transparency) if precision is lost.

---

### 5. AUDIT CONCLUSION
**Status:** **SOUND** (Conditional on `gfx::ToEnclosedRect` invariants).

Blink and `cc` maintain opacity preservation during occlusion culling by adopting a **conservative inward-snapping geometry model** and a **strict multiplicative state check** via the `EffectTree`. Any ambiguity in alpha (anti-aliasing, undecoded images, non-rectilinear clips, or pixel-moving filters) immediately downgrades the region from "Occluder" to "Blended," guaranteeing visual correctness over maximum culling efficiency.

**[AGENT 413 - STANDING BY FOR SPECIFIC CODEBASE INQUIRIES OR CRASH DUMP ANALYSIS]**