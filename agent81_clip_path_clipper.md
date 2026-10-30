# Agent 81 Audit Report: Chromium Blink `ClipPathClipper` vs. CSS Masking Level 1 §3

**Target Component:** `third_party/blink/renderer/core/paint/clip_path_clipper.cc` / `.h`  
**Specification:** W3C CSS Masking Module Level 1, §3 (Clipping Paths: the `clip-path` property)  
**Formal Verification Target:** `BlinkClipPathGeometrySemantics.v`

---

## 1. Core Data Structures in Blink Clip Path Clipping

In Chromium Blink’s Paint phase (post-LayoutNG / CompositeAfterPaint), clipping operations defined by the CSS `clip-path` property are orchestrated by `ClipPathClipper`. The representation and execution of these clips rely on the following core structures:

### 1.1 `ClipPathClipper` (`core/paint/clip_path_clipper.h`)
A stack-allocated (`STACK_ALLOCATED()`) utility class instantiated during the paint lifecycle (`PaintLayerPainter` or `BoxFragmentPainter`). It mediates between the layout tree's `LayoutObject`, the style engine's `ClipPathOperation`, and the graphics context's paint controller.
* **Key Methods:**
  * `LocalReferenceBox(const LayoutObject&)`: Computes the local coordinate space reference box based on the layout object type (SVG vs. CSS box model) and ` geometry-box` keywords (`border-box`, `padding-box`, `content-box`, `fill-box`, `stroke-box`, `view-box`).
  * `ClipPathBoundingBox(...)`: Computes the world- or local-space axis-aligned bounding box (AABB) of the active clip path.
  * ` ShouldUseMaskBasedClip(...)`: Determines whether the clip can be accelerated via a hardware/Skia `ClipPathDisplayItem` (direct raster/GPU stencil) or requires falling back to an offscreen `PaintRecord` composited with `SkBlendMode::kDstIn` (mask-based clip, e.g., when complex SVG `<clipPath>` contains multiple shapes, text, or nested masks).

### 1.2 `ClipPathOperation` (`core/style/clip_path_operation.h`)
An abstract base class representing the parsed value of the CSS `clip-path` property stored inside `ComputedStyle`. It uses an internal discriminator enum `OperationType`:
1. **`ShapeClipPathOperation` (`kShape`)**: Wraps a `scoped_refptr<const BasicShape>` (`inset()`, `circle()`, `ellipse()`, `polygon()`, `path()`, `rect()`, `xywh()`) alongside a `GeometryBox` enum.
2. **`ReferenceClipPathOperation` (`kReference`)**: Holds an `AtomicString` URL fragment identifier pointing to a `LayoutSVGResourceClipper` (`<clipPath>` element in the DOM).
3. **`GeometryBoxClipPathOperation` (`kGeometryBox`)**: Represents a standalone `<geometry-box>` value where the box itself acts as the clip path.

### 1.3 `FloatRoundedRect` and `gfx::RectF` (`platform/geometry/float_rounded_rect.h`)
Represents an axis-aligned rectangle (`gfx::RectF`) coupled with four `gfx::SizeF` corner radii (`TopLeft`, `TopRight`, `BottomLeft`, `BottomRight`). 
* Used as a fast-path optimization in Blink: if `ShapeClipPathOperation` is an `inset()` or `circle()`/`ellipse()` that resolves to a valid rounded rectangle (`BasicShape::GetType() == kBasicShapeInsetType`), Blink bypasses general Bezier path tessellation and emits a hardware-accelerated `FloatRoundedRect` clip (`SkRRect`).
* Enforces structural invariants: $\text{width} \ge 0$, $\text{height} \ge 0$, and corner radii sum constraints ($\text{radii}_x \le \text{width}$, $\text{radii}_y \le \text{height}$ via `ConstrainRadii()`).

### 1.4 `Path` (`platform/graphics/path.h`)
A wrapper around Skia’s `SkPath`. It represents arbitrary 2D vector geometry composed of move, line, quadratic, conic, and cubic Bezier verbs, paired with a `WindRule` (`RULE_NONZERO` or `RULE_EVENODD`, corresponding to CSS `nonzero` and `evenodd`).
* `BasicShape::GetPath(Path&, const gfx::RectF& bounding_box, float zoom)` resolves functional CSS shapes into concrete coordinates inside `Path`.
* `Path::BoundingRect()` returns a `gfx::RectF` enclosing all control points (or tight bounds) of the underlying `SkPath`.

### 1.5 `DisplayItemClient` (`platform/graphics/paint/display_item_client.h`)
The paint invalidation and caching identity token. When `ClipPathClipper` emits a `ClipPathRecorder` or `PaintChunk` with `ClipPaintPropertyNode`, the `LayoutObject` (or a dedicated `SynthesizedClip`) acts as the `DisplayItemClient`. This ensures that mutations to the `ClipPathOperation` or the `LocalReferenceBox` invalidate the cached display list items and raster tiles.

---

## 2. Clip Evaluation and Coordinate Mapping

According to **CSS Masking Level 1 §3.1**, a clipping path restricts the region to which paint can be applied. Any parts of the element that lie outside the region bounded by the currently active clipping path are not drawn.

```
+-------------------------------------------------------------------+
| Target Element Painting Context (Local Coordinate Space)          |
|                                                                   |
|   +-------------------------------------------+                   |
|   | LocalReferenceBox (R_ref : gfx::RectF)    |                   |
|   |                                           |                   |
|   |        .......................            |                   |
|   |     ...                       ...         |                   |
|   |    .     Clip Geometry (G_clip)  .        |                   |
|   |   .   +-----------------------+   .       |                   |
|   |   .   | Intersected Region    |   .       |                   |
|   |    .  | R_out = R_target ∩ G  |  .        |                   |
|   |     ...                       ...         |                   |
|   +-------|-----------------------|-----------+                   |
|           |                       |                               |
|           +-----------------------+                               |
|           Target Paint Bounds (R_target)                          |
+-------------------------------------------------------------------+
```

### 2.1 Reference Box Resolution
Given a target `LayoutObject`, `ClipPathClipper::LocalReferenceBox` computes $R_{\text{ref}} = (x_r, y_r, w_r, h_r) \in \mathbb{R}^2 \times \mathbb{R}_{\ge 0}^2$.
* For CSS boxes, `GeometryBox` selects the border, padding, or content box in physical coordinates relative to the object's local paint offset.
* For SVG elements, `SVGResources::ComputeReferenceBox` computes either the `fill-box` (`ObjectBoundingBox`), `stroke-box` (`StrokeBoundingBox`), or `view-box` (nearest SVG viewport dimensions).

### 2.2 Evaluation: Basic Shapes vs. SVG `<clipPath>`
1. **`ShapeClipPathOperation` Evaluation:**
   Percentages in `<basic-shape>` functions are resolved against $R_{\text{ref}}$:
   * Horizontal lengths resolve against $w_r$, vertical against $h_r$.
   * Circular radii resolve against $\frac{\sqrt{w_r^2 + h_r^2}}{\sqrt{2}}$.
   * The resulting `Path` $P_{\text{shape}}$ is translated by $(x_r, y_r)$ so that it resides in the target’s local paint coordinate space.

2. **`ReferenceClipPathOperation` (SVG `<clipPath>`) Evaluation:**
   Resolved via `LayoutSVGResourceClipper`. The coordinate mapping depends on `clipPathUnits`:
   * **`userSpaceOnUse`**: The `<clipPath>` children are evaluated directly in the coordinate system of the target element's current user space (subject to an optional `transform` attribute $M_{\text{clip}}$ on the `<clipPath>` element).
   * **`objectBoundingBox`**: An affine transformation matrix $M_{\text{obb}}$ is constructed and pre-multiplied before evaluating the `<clipPath>` geometry:
     $$M_{\text{obb}} = \begin{bmatrix} w_r & 0 & x_r \\ 0 & h_r & y_r \\ 0 & 0 & 1 \end{bmatrix}$$
     Thus, coordinates $[0, 1] \times [0, 1]$ inside the `<clipPath>` map bijectively (assuming $w_r, h_r > 0$) onto $R_{\text{ref}}$.

### 2.3 Intersection with Target Bounding Box
Let $\Omega_{\text{target}} \subseteq \mathbb{R}^2$ be the unpainted visual overflow region of the target element (bounded by $B(\Omega_{\text{target}}) = R_{\text{target}}$), and let $\Omega_{\text{clip}} \subseteq \mathbb{R}^2$ be the closed interior point-set defined by the evaluated `Path` (under its `WindRule`) or `FloatRoundedRect`.

The effective painted region $\Omega_{\text{out}}$ is the set-theoretic intersection:
$$\Omega_{\text{out}} = \Omega_{\text{target}} \cap \Omega_{\text{clip}}$$

At the bounding-box level (`ClipPathClipper::ClipPathBoundingBox` intersected with the paint chunk bounds in `PaintPropertyTreeBuilder`), the resulting Axis-Aligned Bounding Box (AABB) is:
$$B_{\text{out}} = B(\Omega_{\text{target}}) \cap_{\text{AABB}} B(\Omega_{\text{clip}})$$
 Note that because bounding box extraction is a conservative over-approximation ($\Omega \subseteq B(\Omega)$), we have the fundamental inclusion:
$$\Omega_{\text{out}} = \Omega_{\text{target}} \cap \Omega_{\text{clip}} \subseteq B(\Omega_{\text{target}}) \cap B(\Omega_{\text{clip}}) = B_{\text{out}}$$

---

## 3. Monotonic Intersection and Bounding Box Containment

A critical safety and rendering invariant in Blink's property tree computation (`ClipPaintPropertyNode` and `gfx::RectF::Intersect`) is that clipping is strictly **contractive** (monotonic decreasing with respect to set inclusion and Lebesgue measure/area) and preserves **bounding box well-formedness** (non-negativity of dimensions).

### 3.1 Point-Set and Area Monotonicity
Let $\mu : \mathcal{B}(\mathbb{R}^2) \to \mathbb{R}_{\ge 0}$ denote the standard 2D Lebesgue measure (area). For any measurable target region $A \subseteq \mathbb{R}^2$ and clip region $C \subseteq \mathbb{R}^2$:
$$A \cap C \subseteq A \implies \mu(A \cap C) \le \mu(A)$$
In Blink, this guarantees that applying a `ClipPathOperation` can never expand the visual overflow rect or require allocating a larger backing texture/compositor surface than the unclipped target (unless filters are applied post-clip, which sit in a separate `EffectPaintPropertyNode`).

### 3.2 Bounding Box Intersection Semantics (`gfx::RectF::Intersect`)
Let an AABB be defined by its interval projections $R = [x_1, x_2] \times [y_1, y_2]$ where $w = \max(0, x_2 - x_1)$ and $h = \max(0, y_2 - y_1)$. Alternatively, in origin-size representation $R = (x, y, w, h)$ with $w \ge 0, h \ge 0$:
$$x_1 = x, \quad x_2 = x + w, \quad y_1 = y, \quad y_2 = y + h$$

Given two valid bounding boxes $R_A = (x_A, y_A, w_A, h_A)$ and $R_B = (x_B, y_B, w_B, h_B)$, Blink computes $R_A \cap_{\text{AABB}} R_B$ as:
1. $x'_1 = \max(x_A, x_B)$, $\quad y'_1 = \max(y_A, y_B)$
2. $x'_2 = \min(x_A + w_A, x_B + w_B)$, $\quad y'_2 = \min(y_A + h_A, y_B + h_B)$
3. **Non-negativity clamping (Disjoint handling):**
   If $x'_1 \ge x'_2$ or $y'_1 \ge y'_2$, the intersection is empty, and Blink normalizes the rect to $(0, 0, 0, 0)$ (or retains origin with $w' = 0, h' = 0$). In interval width terms:
   $$w' = \max(0, x'_2 - x'_1), \quad h' = \max(0, y'_2 - y'_1)$$

**Theorem (Dimension Non-Negativity & Area Monotonicity):**
For any $R_A, R_B$ with $w_A, h_A, w_B, h_B \ge 0$:
1. $w' \ge 0 \land h' \ge 0$.
2. $w' \le w_A \land h' \le h_A$.
3. $\text{Area}(R_A \cap_{\text{AABB}} R_B) = w' \cdot h' \le w_A \cdot h_A = \text{Area}(R_A)$.

*Proof Sketch:* Since $x'_1 = \max(x_A, x_B) \ge x_A$ and $x'_2 = \min(x_A + w_A, x_B + w_B) \le x_A + w_A$, we have $x'_2 - x'_1 \le (x_A + w_A) - x_A = w_A$. Because $w_A \ge 0$, $\max(0, x'_2 - x'_1) \le w_A$. Identical reasoning holds for $h' \le h_A$. Because $0 \le w' \le w_A$ and $0 \le h' \le h_A$, bilinear monotonicity over $\mathbb{R}_{\ge 0}$ yields $w' \cdot h' \le w_A \cdot h_A$. $\blacksquare$

---

## 4. Idempotence of Repeated Clipping Operations

In Blink, a `ClipPathOperation` can be applied across multiple stages or nested contexts (e.g., when a `ClipPaintPropertyNode` is intersected during `PaintChunk` culling, and subsequently applied as a Skia clip in `ClipPathClipper`, or when an SVG `<use>` / nested `<clipPath>` references an identical clip geometry in the same coordinate space).

### 4.1 Set-Theoretic Idempotence
At the exact geometry level (both `FloatRoundedRect` analytic regions and `Path` winding interiors):
$$(\Omega_{\text{target}} \cap \Omega_{\text{clip}}) \cap \Omega_{\text{clip}} = \Omega_{\text{target}} \cap (\Omega_{\text{clip}} \cap \Omega_{\text{clip}}) = \Omega_{\text{target}} \cap \Omega_{\text{clip}}$$
Crucially, even though an SVG `Path` may use `RULE_EVENODD` to determine whether a point $p \in \