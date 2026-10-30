# Chromium Blink View Transition Layout vs. W3C CSS View Transitions Level 1 Audit
**Agent 13 Formal Verification & Layout Architecture Report**

---

## 1. Core Data Structures in Blink View Transition Layout

Chromium’s implementation of CSS View Transitions Level 1 bridges the DOM/Style engine (`third_party/blink/renderer/core/view_transition/`) and the LayoutNG pipeline (`third_party/blink/renderer/core/layout/`) alongside the Viz compositor (`components/viz/common/view_transition_element_resource_id.h`).

### 1.1 `ViewTransitionStyleTracker`
Located in `view_transition_style_tracker.h/.cc`, this state machine manages the lifecycle, geometry capture, and dynamic UA stylesheet generation for the pseudo-element tree.
* **`ElementData` (Inner Struct):** Tracks per-tag state across the transition phases (`kCapture`, `kAnimate`, `kFinished`).
  * `target_element`: `Member<Element>` pointing to the live DOM node.
  * `cached_container_properties`: `Vector<ContainerProperties>` storing border-box dimensions and screen-space transforms before (`old`) and after (`new`) the DOM mutation.
  * `visual_overflow_rect_in_layout_space`: `PhysicalRect` representing the painted ink overflow (drop shadows, outlines, out-of-flow descendants) relative to the element's border box.
  * `captured_rect_in_layout_space`: The clipped subset of the visual overflow rect when constrained by the maximum texture allocation limit ($M_{\text{tex}}$, typically 4096px or 8192px) or the Snapshot Root viewport.
  * `old_snapshot_id` / `new_snapshot_id`: `viz::ViewTransitionElementResourceId` bindings linking Blink layout fragments to GPU render pass textures in Viz.
* **`ContainerProperties` Struct:**
  ```cpp
  struct ContainerProperties {
    PhysicalSize border_box_size_in_css_space;
    gfx::Transform snapshot_matrix; // Maps local border-box to Snapshot Root space
  };
  ```
* **`captured_name_map_`:** `HeapHashMap<AtomicString, Member<ElementData>>` mapping `view-transition-name` identifiers to their state records.

### 1.2 Pseudo-Element Tree & `PseudoElement` Subclasses
The transition tree is rooted at the document's top-layer (`::view-transition`) and instantiated via `ViewTransitionPseudoElementBase` (inheriting from `PseudoElement`):

1. **`::view-transition` (`kPseudoIdViewTransition`):** The Snapshot Containing Block root. Covers the layout viewport, establishes an absolute positioning context, and isolates stacking (`isolation: isolate`).
2. **`::view-transition-group(name)` (`kPseudoIdViewTransitionGroup`):** Positioned at the origin of `::view-transition`. Animates size (`width`, `height`) and geometry (`transform`) between the `old` and `new` `ContainerProperties`.
3. **`::view-transition-image-pair(name)` (`kPseudoIdViewTransitionImagePair`):** `position: absolute; inset: 0; isolation: isolate`. Serves as the isolation group for `plus-lighter` cross-fade blending.
4. **`::view-transition-old(name)` & `::view-transition-new(name)` (`kPseudoIdViewTransitionOld`, `kPseudoIdViewTransitionNew`):** Replaced elements backed by `LayoutViewTransitionContent` (inheriting from `LayoutReplaced`). They consume the `viz::ViewTransitionElementResourceId` and expose the captured texture as a replaced content box.

### 1.3 LayoutNG Integration & `LayoutViewTransitionContent`
While standard block/absolute layout algorithms (`BlockLayoutAlgorithm`, `OutOfFlowLayoutPart`) handle `::view-transition`, `::view-transition-group`, and `::view-transition-image-pair` as regular boxes governed by dynamically injected UA CSS rules, the leaf nodes use a specialized replaced layout pipeline:
* **`LayoutViewTransitionContent` (`layout_view_transition_content.h`):** Overrides `IntrinsicSizingInfo` calculation. It holds:
  * `captured_rect_`: `gfx::RectF` (the offset and dimensions of the texture relative to the element's border box).
  * `reference_rect_in_enclosing_layer_space_`: `gfx::RectF` (the captured element's border box in enclosing layer coordinates).
  * `propagate_max_extent_rect_`: Boolean controlling ink-overflow clipping vs. expansion.
* **`ViewTransitionContentLayoutAlgorithm` / Replaced Layout:** In LayoutNG, `LayoutViewTransitionContent` feeds into `LayoutReplaced` sizing logic via `ComputeReplacedSize`. The layout pass generates a `PhysicalBoxFragment` whose paint phase (`ViewTransitionContentPainter`) emits a `cc::ViewTransitionContentLayer` or `viz::TextureDrawQuad` scaled from `captured_rect_` into `reference_rect_`.

---

## 2. Layout Sizing and Positioning Algorithm

Let $D_{\text{dpr}} \in \mathbb{R}_{>0}$ be the device pixel ratio (`device_scale_factor`). All raw layout captures occur in physical device pixels and are normalized to CSS pixels for UA style injection.

### 2.1 Snapshot Intrinsic Size Preservation
For a captured element $E$, let its border-box size in physical pixels be $B_{\text{phys}} = (W_{\text{phys}}, H_{\text{phys}})$ and its ink-overflow rect (relative to the border-box origin) be $O_{\text{phys}} = (x_o, y_o, w_o, h_o)$.

1. **CSS Space Border Box:**
   $$W_{\text{css}} = \frac{W_{\text{phys}}}{D_{\text{dpr}}}, \quad H_{\text{css}} = \frac{H_{\text{phys}}}{D_{\text{dpr}}}$$
2. **Intrinsic Size of `::view-transition-old/new`:**
   In `LayoutViewTransitionContent::IntrinsicSizingInfo`, the intrinsic size reported to the CSS sizing algorithm is the **reference rect** (the border box), *not* the visual overflow rect:
   $$W_{\text{intrinsic}} = W_{\text{css}}, \quad H_{\text{intrinsic}} = H_{\text{css}}$$
   $$R_{\text{intrinsic}} = \begin{cases} W_{\text{css}} / H_{\text{css}} & \text{if } H_{\text{css}} > 0 \\ \text{none} & \text{if } H_{\text{css}} = 0 \end{cases}$$
3. **Ink Overflow Offset Compensation:**
   Because the GPU texture actually captures $O_{\text{phys}}$ (clipped to $C_{\text{phys}} = (x_c, y_c, w_c, h_c)$), `LayoutViewTransitionContent` maps the layout content box $(0, 0, W_{\text{layout}}, H_{\text{layout}})$ to the texture quad by applying a scale factor $(S_x, S_y) = \left(\frac{W_{\text{layout}}}{W_{\text{css}}}, \frac{H_{\text{layout}}}{H_{\text{css}}}\right)$ and shifting the painted quad to:
   $$\text{QuadRect} = \left( \frac{x_c}{D_{\text{dpr}}} S_x,\; \frac{y_c}{D_{\text{dpr}}} S_y,\; \frac{w_c}{D_{\text{dpr}}} S_x,\; \frac{h_c}{D_{\text{dpr}}} S_y \right)$$

### 2.2 Transform Matrix Computation
During capture (`ViewTransitionStyleTracker::Capture`), Blink computes the transform mapping the element's local coordinate space to the **Snapshot Root** coordinate space:

1. Compute local-to-screen transform $T_{\text{local}\to\text{screen}} \in \mathbb{R}^{4\times 4}$ via `LayoutObject::LocalToAbsoluteTransform()`.
2. Compute Snapshot Root-to-screen transform $T_{\text{snap}\to\text{screen}} \in \mathbb{R}^{4\times 4}$ (accounting for mobile URL bar offsets, pinch-zoom, or fixed-position root shifts).
3. The snapshot matrix in physical space is:
   $$M_{\text{phys}} = T_{\text{snap}\to\text{screen}}^{-1} \cdot T_{\text{local}\to\text{screen}}$$
4. **2D Flattening Mandate (W3C Spec § 4.2):** If the element or an ancestor has 3D transforms without `transform-style: preserve-3d` extending into the transition context, $M_{\text{phys}}$ is flattened to a 2D affine matrix in the XY plane by zeroing the 3rd row and 3rd column (except $m_{33}=1$).
5. **CSS Space Normalization:** Let $S(d) = \text{diag}(d, d, 1, 1)$. The matrix injected into the UA stylesheet for `::view-transition-group(name)` is:
   $$M_{\text{css}} = S(D_{\text{dpr}})^{-1} \cdot M_{\text{phys}} \cdot S(D_{\text{dpr}})$$
   Specifically, the translation components $(m_{14}, m_{24})$ are divided by $D_{\text{dpr}}$, while rotational and scaling components remain scale-invariant.

### 2.3 Aspect-Ratio Preserving Fit
By default, the UA stylesheet assigns:
```css
::view-transition-old(*), ::view-transition-new(*) {
  position: absolute;
  inset-block-start: 0;
  inset-inline-start: 0;
  inline-size: 100%;
  block-size: auto;
}
```
During transition frame $t \in [0, 1]$, `::view-transition-group(name)` has interpolated dimensions $(W_g(t), H_g(t))$ (in horizontal-tb writing mode, `inline-size` corresponds to width $W_g(t)$ and `block-size` to height $H_g(t)$).

For either replacement pseudo-element $p \in \{\text{old}, \text{new}\}$ with intrinsic dimensions $(W_p, H_p)$ and aspect ratio $R_p = W_p / H_p$:
1. The Definite Inline Size resolves to $W_{\text{used}}(t) = W_g(t)$.
2. Because `block-size` is `auto`, LayoutNG's `ComputeReplacedSize` resolves the block size using the definite inline size and the intrinsic aspect ratio $R_p$:
   $$H_{\text{used}}(t) = \frac{W_{\text{used}}(t)}{R_p} = W_g(t) \cdot \frac{H_p}{W_p}$$
3. **Object-Fit Resolution (`LayoutReplaced::ComputeObjectFitAndPositionRect`):**
   If the author overrides `block-size: 100%` alongside `object-fit: contain | cover | scale-down | none`:
   Let container box be $B_c = (W_g(t), H_g(t))$ with ratio $R_c = W_g(t)/H_g(t)$. The painted content destination rect $(W_{\text{dest}}, H_{\text{dest}})$ is:
   $$(W_{\text{dest}}, H_{\text{dest}}) = \begin{cases} 
   (W_g(t), H_g(t)) & \text{if } \text{fill} \\
   \left(W_g(t), \frac{W_g(t)}{R_p}\right) & \text{if } (\text{contain} \land R_p \ge R_c) \lor (\text{cover} \land R_p < R_c) \\
   \left(H_g(t) \cdot R_p, H_g(t)\right) & \text{if } (\text{contain} \land R_p < R_c) \lor (\text{cover} \land R_p \ge R_c) \\
   (W_p, H_p) & \text{if } \text{none}
   \end{cases}$$

---

## 3. Containing Block Override and Root Pseudo-Element Viewport Projection

### 3.1 The Snapshot Containing Block (SCB)
W3C CSS View Transitions Level 1 defines the **Snapshot Containing Block** as a rectangle covering the layout viewport plus any dynamic browser UI areas (e.g., mobile top/bottom bars in their retracted state).

In Blink (`LayoutView::GetSnapshotContainingBlockInfo()` and `ViewTransitionStyleTracker::GetSnapshotRootSize()`):
* **Origin:** Anchored at the physical origin of the visual/frame viewport when the mobile URL bar is shown, or shifted by $-\Delta_{\text{url\_bar}}$ so the SCB covers the maximally expanded viewport.
* **Containing Block Override:**
  In `LayoutObject::ContainingBlock()`, `::view-transition` is a child of `LayoutView` (the Initial Containing Block, ICB). However, normal children of `LayoutView` are positioned relative to the scrolled layout viewport or ICB.
  Blink overrides the containing block rectangle for `::view-transition` in `OutOfFlowLayoutPart::GetContainingBlockInfo`:
  * Its `position` is forced to `fixed` (conceptually anchored to the SCB, immune to root document scroll offsets $(S_x, S_y)$).
  * Its containing block dimensions are set to `ViewTransitionStyleTracker::GetSnapshotRootSize()`.

### 3.2 Root Pseudo-Element Viewport Projection
When the root element (`document.documentElement`, `view-transition-name: root`) is captured:
1. Unlike normal DOM elements whose capture bounds are their `BorderBoxRect()`, the root element can have arbitrary scroll dimensions $(W_{\text{doc}}, H_{\text{doc}}) \gg (W_{\text{scb}}, H_{\text{scb}})$.
2. Blink intercepts the root capture in `ViewTransitionStyleTracker::AddTransitionElementsFromCSS`:
   * The captured `border_box_size_in_css_space` is clamped and projected onto the **Snapshot Containing Block** size $(W_{\text{scb}}, H_{\text{scb}})$.
   * The `snapshot_matrix` for `root` is set to the identity transform $I_4$ in SCB space (meaning the currently visible scrolled viewport region $[S_x, S_x + W_{\text{scb}}] \times [S_y, S_y + H_{\text{scb}}]$ is projected onto $[0, W_{\text{scb}}] \times [0, H_{\text{scb}}]$).
   * In `PaintLayerPainter` / `ViewTransitionSupplement`, root background painting is hoisted into the root snapshot pass, and the live root painters are suppressed via `PaintFlag::kOmitCompositingInfo` to prevent double-painting.

---

## 4. Mathematical Invariants, Edge Cases, and Specification Gaps

### 4.1 Formal Mathematical Invariants
1. **Invariant 1 (Non-Negative Fragment Dimensions):**
   $$\forall t \in [0,1], \; \forall E \in \text{CapturedElements}: \quad W_g(t) \ge 0 \land H_g(t) \ge 0 \land W_{\text{used}}(t) \ge 0 \land H_{\text{used}}(t) \ge 0$$
2. **Invariant 2 (Snapshot Aspect Ratio Preservation under Default