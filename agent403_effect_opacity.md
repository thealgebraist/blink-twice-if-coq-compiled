**AUDIT LOG: AGENT 403**
**TARGET:** Chromium Blink / cc (Compositor) Render Pipeline
**SUBJECT:** Effect Tree Opacity Product & Multiplicative Attenuation

---

### 1. ARCHITECTURAL OVERVIEW
In the Blink Compositor (`cc`), visual effects such as opacity, filters, and blend modes are decoupled from geometry (Transform Tree) and scrolling (Scroll Tree). They are represented as nodes within the **Effect Tree** (`cc::EffectTree`). 

Multiplicative opacity attenuation is the mathematical and architectural mechanism by which fractional opacity values cascade down the hierarchy of `cc::EffectNode` instances, reducing the alpha channel of descendant layers and render surfaces before final rasterization and display composition.

### 2. THE MATHEMATICAL MODEL
The fundamental equation governing multiplicative attenuation across an arbitrary branch of the Effect Tree from the Root Node ($i=0$) to a leaf Effect Node ($i=n$) is:

$$\alpha_{\text{effective}} = \prod_{i=0}^{n} \alpha_i$$

Where $\alpha_i \in [0.0, 1.0]$ represents the local `opacity` property defined on `EffectNode` $i$. 

Because standard floating-point multiplication is associative and commutative, the compositor attempts to optimize this product. However, **Group Opacity** requirements (per the W3C CSS Color Module specification) strictly dictate *when* this product can be collapsed into a single scalar vs. when it requires intermediate offscreen texture allocation.

---

### 3. ATTENUATION PATHS IN `cc`

#### Path A: Fast-Path (DrawQuad Property Collapse)
If an `EffectNode` and its ancestors have $\alpha < 1.0$, and **no node** in the chain requires a Render Surface (i.e., no overlapping descendants, no complex backdrop filters, no non- associative blend modes), the compositor flattens the attenuation.

1. During `draw_property_utils::ComputeSurfaceDrawProperties`, the `EffectTree` is traversed.
2. The `screen_space_opacity` of a node is calculated directly as:
   `node->screen_space_opacity = node->opacity * parent_node->screen_space_opacity;`
3. When generating `viz::DrawQuad` instances for a layer attached to this node, the `SharedQuadState::opacity` is populated with this pre-multiplied `screen_space_opacity`.
4. **GPU Execution:** The GPU shader multiplies the fragment's source color (in premultiplied alpha space) by this single scalar value in one pass.

#### Path B: Slow-Path (RenderSurface Pass Attenuation)
If an `EffectNode` has $\alpha < 1.0$ **and** possesses multiple overlapping descendants (or sets `HasRenderSurface() == true` via `RenderSurfaceReason::kOpacity`), collapsing the opacity product directly into the leaf Quads will cause visual artifacts (overlapping regions will bleed through each other).

To preserve correct group attenuation:
1. **Pass Isolation:** The Effect Node forces the allocation of an intermediate `cc::RenderSurfaceImpl` (which maps to a `viz::CompositorRenderPass`).
2. **Local Attenuation Reset:** Descendants of this node do *not* inherit its opacity in their `screen_space_opacity` calculation. Their product calculation restarts at `1.0` relative to the intermediate surface.
3. **Composite Draw:** The descendants are drawn at their local opacities into the intermediate texture (FBO).
4. **Parent Attenuation:** The intermediate texture is then represented as a `viz::CompositorRenderPassDrawQuad` in the *parent* Render Pass. The `EffectNode->opacity` is applied to this specific Quad's `SharedQuadState`.

---

### 4. COLOR SPACE & PREMULTIPLIED ALPHA
The compositor operates strictly in **Premultiplied Alpha** space for blending operations. Multiplicative attenuation of a pixel $C = (R_p, G_p, B_p, A)$ by an Effect Node's effective opacity ($\alpha_e$) is executed in the fragment shader as a uniform vector scale:

$$C_{\text{out}} = C_{\text{in}} \cdot \alpha_e = (R_p \cdot \alpha_e, \quad G_p \cdot \alpha_e, \quad B_p \cdot \alpha_e, \quad A \cdot \alpha_e)$$

**Audit Note on Precision Loss (Quantization):**
When Path B (RenderSurface) is triggered on an 8-bit-per-channel (`RGBA_8888`) pipeline, multiplicative attenuation occurs in discrete stages.
$$\text{Value}_{\text{final}} = \lfloor \lfloor C_{\text{initial}} \cdot \alpha_{\text{child}} + 0.5 \rfloor \cdot \alpha_{\text{parent}} + 0.5 \rfloor$$
Deeply nested Effect Nodes forcing multiple RenderSurfaces with fractional opacities will accumulate quantization error, resulting in premature alpha-zeroing (banding/clipping) compared to Path A, which retains `float32` precision until the final fragment shader stage.

---

### 5. EDGE CASES & OPTIMIZATION AUDITS

*   **Zero-Opacity Short-Circuit ($\alpha = 0.0$):** 
    If any `EffectNode` in the product chain evaluates to `0.0f` (and is not actively running a CC-driven opacity animation), `draw_property_utils` flags the subtree as invisible. Cull rects drop the layers, and `DrawQuad` generation is bypassed entirely. If an animation *is* present (`node->is_currently_animating_opacity`), the subtree is kept alive to prevent raster-inducing tree rebuilds on the next frame.
*   **1.0f Identity Elision:**
    Nodes with `opacity == 1.0f` act as identity elements in the product. Blink's `PropertyTreeBuilder` actively avoids creating `EffectNode` instances for DOM elements with default opacity unless required by other grouping properties (`will-change: opacity`, `filter`, `mix-blend-mode`).
*   **3D Rendering Contexts (`preserve-3d`):**
    Per CSS Transforms Level 2, `opacity < 1.0` forces flattening (grouping). Therefore, an `EffectNode` with fractional opacity breaks `preserve-3d` hierarchies, forcing a RenderSurface and preventing 3D depth-sorting across the attenuation boundary.

**STATUS:** Audit Complete. Multiplicative attenuation logic within `cc::EffectTree` conforms to expected compositor invariants.