# Agent 5 Audit Report: Chromium Blink CSS Shapes vs. W3C CSS Shapes Module Level 1

**Scope:** `third_party/blink/renderer/core/layout/shapes/`  
**Specification:** W3C CSS Shapes Module Level 1 (CR / ED)  
**Target Formalization:** `BlinkShapeOutsideSemantics.v`

---

## 1. Core Data Structures in Blink Shapes

Blink’s CSS Shapes implementation translates declarative CSS properties (`shape-outside`, `shape-margin`, `shape-image-threshold`) into geometric query structures that the Inline Layout algorithm (LayoutNG) intersects with line boxes to determine excluded inline intervals.

### `ShapeOutsideInfo` (`shape_outside_info.h/.cc`)
* **Role:** The bridge between `LayoutBox` (specifically floating boxes) and the underlying geometric `Shape` instance. Owned via `std::unique_ptr` or GarbageCollected mechanisms mapped to the float's `LayoutBox`.
* **State:** Caches the computed `std::unique_ptr<Shape> shape_`, the `reference_box_logical_size_`, and `percentage_resolution_inline_size_`.
* **Coordinate Space:** Translates line-relative coordinates (from the formatting context) into the shape’s internal logical coordinate space (where $X$ is inline-axis and $Y$ is block-axis, accounting for `writing-mode`).

### `Shape` (`shape.h/.cc`)
* **Role:** Abstract base class representing a resolved 2D geometry in logical coordinates.
* **Key Properties:** `writing_mode_`, `float_margin_box_size_`, and `margin_` (resolved `shape-margin` in CSS pixels as `float`).
* **Core Virtual API:** 
  * `LogicalRect ShapeMarginLogicalBoundingBox() const`
  * `LineSegment GetExcludedInterval(LayoutUnit logical_top, LayoutUnit logical_height) const`

### `LineSegment` and `SegmentList` (`shape.h`, `shape_interval.h`)
* **`ShapeInterval<T>` (`shape_interval.h`):** A generic 1D interval $[x_1, x_2]$ where $x_1 \le x_2$. Provides set-theoretic operations (`Unite`, `Intersect`, `Subtract`, `Overlaps`, `Contains`).
* **`LineSegment` (`shape.h`):** Represents the *final* excluded horizontal span for a single float at a given line height.
  ```cpp
  struct LineSegment {
    LayoutUnit logical_left;
    LayoutUnit logical_right;
    bool is_valid; // False if the shape does not intersect the line box [y1, y2]
  };
  ```
* **`SegmentList`:** `Vector<LineSegment>` or `Vector<FloatShapeInterval>`. While `PolygonShape` and `RasterShape` can generate multiple disjoint horizontal intervals per scanline internally, CSS Shapes Level 1 dictates that `shape-outside` only affects the wrapping on the side opposite the float (or rather, merges intervals into a single bounding exclusion span `[min_x, max_x]`). Blink collapses `Vector<FloatShapeInterval>` into a single `LineSegment` before returning to inline layout.

### `BoxShape` (`box_shape.h/.cc`)
* **Representation:** Wraps a `FloatRoundedRect` (an axis-aligned rectangle with four independent elliptical corner radii: `FloatSize` for TopLeft, TopRight, BottomLeft, BottomRight).
* **Margin Handling:** `shape-margin` is baked directly into the `BoxShape` upon construction by calling `FloatRoundedRect::OutsetForShapeMargin(margin)`.

### `PolygonShape` (`polygon_shape.h/.cc`)
* **Representation:** A closed planar polygon defined by `Vector<FloatPoint> vertices_` and a fill rule (`WindRule::kRuleNonZero` or `WindRule::kRuleEvenOdd`, though W3C CSS Shapes Level 1 restricts `GetExcludedInterval` to the bounding hull of all intersections, effectively neutralizing interior holes!).
* **Internal Accelerators:** Computes `PolygonEdge` objects (`FloatPolygonEdge`), which are sorted or queried via an `OffsetPolygonEdge` structure to handle `shape-margin` dilation dynamically during scanline intersection.

---

## 2. Line Segment Calculation (Scanline Intersection)

Given a line box spanning block-axis interval $[y_1, y_2]$ (where $y_1 = \text{logical\_top}$ and $y_2 = y_1 + \text{logical\_height}$), Blink computes the excluded inline interval $[x_{\text{left}}, x_{\text{right}}]$ via `Shape::GetExcludedInterval(y1, height)`.

### A. `BoxShape::GetExcludedInterval(y1, y2)`
For a rounded rectangle $R = [X_{\min}, X_{\max}] \times [Y_{\min}, Y_{\max}]$ with corner ellipses:
1. **Bounding Box Check:** If $[y_1, y_2]$ does not overlap $[Y_{\min}, Y_{\max}]$, return an invalid `LineSegment`.
2. **Vertical Zone Classification:**
   Let $y_{\text{top\_corner}} = \max(Y_{\min} + r_{TL, y}, Y_{\min} + r_{TR, y})$ and $y_{\text{bot\_corner}} = \min(Y_{\max} - r_{BL, y}, Y_{\max} - r_{BR, y})$.
   If the interval $[y_1, y_2]$ intersects the vertical middle band $[y_{\text{top\_corner}}, y_{\text{bot\_corner}}]$ (or spans across a corner's horizontal extreme), the excluded interval immediately saturates to the full width $[X_{\min}, X_{\max}]$.
3. **Elliptical Corner Intersection (`XInterceptsAtY`):**
   If $[y_1, y_2]$ lies strictly within the top or bottom corner regions, Blink evaluates the ellipse equation at the vertical boundary closest to the vertical center of the box:
   * For a top corner with center $(c_x, c_y)$ and radii $(r_x, r_y)$, the widest horizontal extent in $[y_1, y_2] \cap [Y_{\min}, c_y]$ occurs at $y^* = \min(y_2, c_y)$.
   * The horizontal offset from the ellipse center is computed via:
     $$\Delta x = r_x \sqrt{1 - \left(\frac{y^* - c_y}{r_y}\right)^2}$$
   * Thus, for the top-left corner: $x_{\text{left}} = c_{TL,x} - \Delta x_{TL}$.

### B. `PolygonShape::GetExcludedInterval(y1, y2)`
For a polygon with vertices $V_0, V_1, \dots, V_{n-1}$:
1. **Scanline Band vs. Edges:** An edge $E_i = (P_i, P_{i+1})$ (or its margin-dilated offset shape) is tested for intersection with the horizontal strip $Y \in [y_1, y_2]$.
2. **Zero-Height Line Optimization:** If $y_1 = y_2$, Blink performs standard scanline-edge intersection:
   $$x(y_1) = x_a + \frac{y_1 - y_a}{y_b - y_a}(x_b - x_a)$$
3. **Non-Zero Height Band $[y_1, y_2]$:**
   A line box has thickness $h = y_2 - y_1 > 0$. An excluded interval must encompass *all* points of the shape within $Y \in [y_1, y_2]$.
   * **Edge Clipping:** Each polygon edge is clipped to the vertical range $[y_1, y_2]$. If an edge intersects the band, the clipped segment's $X$-extrema $[x_{\min}(E_i), x_{\max}(E_i)]$ are added to the `FloatShapeInterval` list.
   * **Vertex Containment & Horizontal Penetration:** Even if no edges cross $y_1$ or $y_2$, horizontal segments or vertices inside $[y_1, y_2]$ are captured by the edge clipping logic. For edges crossing $y_1$ and $y_2$, the interior of the polygon between pairs of crossing edges (at $y_1$ and at $y_2$) is united into the interval set.
4. **Interval Collapse:** All generated `FloatShapeInterval`s for edges and interior spans are merged using `FloatShapeInterval::Unite`. Finally, because CSS Shapes L1 only supports single-sided float wrapping, Blink takes the bounding interval:
   $$[x_{\text{left}}, x_{\text{right}}] = \left[ \min_{k} I_{k,\text{start}}, \max_{k} I_{k,\text{end}} \right]$$

---

## 3. Shape Margin Expansion (Minkowski Sum Dilation)

The W3C specification defines `shape-margin` ($m \ge 0$) as the locus of all points at distance $\le m$ from at least one point in the shape (i.e., the Minkowski sum $S \oplus B_m(0)$, where $B_m(0)$ is a closed disk of radius $m$).

### A. `InsetShape` / `BoxShape` (`OutsetForShapeMargin`)
When dilating a `FloatRoundedRect` by $m$:
* The outer bounding box expands by $m$ on all four sides: $[X_{\min}-m, X_{\max}+m] \times [Y_{\min}-m, Y_{\max}+m]$.
* Each corner radius $(r_x, r_y)$ is expanded by $m$:
  $$r'_x = \begin{cases} 0 & \text{if } r_x = 0 \land r_y = 0 \text{ (WAIT: Spec says sharp corners become圆!)} \\ r_x + m & \text{otherwise} \end{cases}$$
  *Correction on Blink's implementation:* `FloatRoundedRect::OutsetForShapeMargin(float outset)` adds `outset` to *both* $r_x$ and $r_y$ unconditionally, even if the original corner radius was $(0, 0)$! That is, a sharp rectangle ($r_x = r_y = 0$) with `shape-margin: 10px` becomes a rounded rectangle with circular corners of radius $(10, 10)$.
* **Elliptical Parallel Curve Approximation (Divergence):** For a non-circular ellipse ($r_x \neq r_y > 0$), the true Minkowski sum with a disk of radius $m$ is an 8th-degree algebraic curve (a parallel curve / offset curve of an ellipse), *not* an ellipse with radii $(r_x+m, r_y+m)$. Both W3C CSS Shapes L1 (explicitly or by inheriting `border-radius` spread formulas) and Blink approximate this as an ellipse of radii $(r_x + m, r_y + m)$.

### B. `CircleShape` and `EllipseShape`
* **Circle:** Radius $r$ becomes $r + m$. Exact Minkowski sum.
* **Ellipse:** Radii $(r_x, r_y)$ become $(r_x + m, r_y + m)$ in `EllipseShape::GetExcludedInterval`. Like `BoxShape`, this is an elliptical approximation of the true offset curve.

### C. `PolygonShape` (`OffsetPolygonEdge`)
For a polygon $P$, the Minkowski sum $P \oplus B_m(0)$ consists of:
1. The interior of $P$.
2. For each edge $E_i = (P_i, P_{i+1})$ with outward unit normal $\vec{n}_i = (n_x, n_y)$, a rectangle of width $|E_i|$ and thickness $m$ (or a two-sided ribbon of width $2m$ centered on $E_i$, since interior overlaps don't change the outer hull).
3. At each vertex $V_i$, a circular disk of radius $m$ centered at $V_i$.

In `PolygonShape::GetExcludedInterval(y1, y2)`:
* Instead of constructing a complex planar straight-line graph (PSLG) with circular arcs via a heavy geometry library (like Clipper/Boost.Geometry), Blink computes the $X$-projection of $(E_i \oplus B_m(0)) \cap ([-\infty, \infty] \times [y_1, y_2])$ directly for each edge and vertex!
* **Vertex Disk Intersection:** For each vertex $V_i = (v_x, v_y)$, the intersection of disk $B_m(V_i)$ with the horizontal strip $[y_1, y_2]$ is computed exactly as a `CircleShape` of radius $m$ at $(v_x, v_y)$:
  * The closest $Y \in [y_1, y_2]$ to $v_y$ is $y^* = \text{clamp}(v_y, y_1, y_2)$.
  * If $|y^* - v_y| \le m$, it contributes the interval $[v_x - \sqrt{m^2 - (y^* - v_y)^2}, v_x + \sqrt{m^2 - (y^* - v_y)^2}]$.
* **Edge Ribbon Intersection (`OffsetPolygonEdge`):** Each edge $E_i$ is offset along its normal $\pm m \vec{n}_i$ to form a parallelogram/rectangle, which is clipped against $[y_1, y_2]$ to yield its horizontal span.
* The union of the un-dilated polygon's interval, all edge-offset intervals, and all vertex-disk intervals equals the exact bounding interval of $(P \oplus B_m(0)) \cap (\mathbb{R} \times [y_1, y_2])$.

---

## 4. Mathematical Invariants, Edge Cases, and Divergences

### Mathematical Invariants
1. **Interval Well-Formedness (Ordering):**
   $$\forall S, y_1, y_2.\; y_1 \le y_2 \implies \text{let } I = \text{GetExcludedInterval}(S, y_1, y_2) \text{ in } I.\text{valid} \implies I.\text{left} \le I.\text{right}$$
2. **Band Monotonicity (Vertical Inclusion):**
   $$\forall S, y_1, y_2, y'_1, y'_2.\; [y_1, y_2] \subseteq [y'_1, y'_2] \implies \text{Interval}(S, y_1, y_2) \subseteq \text{Interval}(S, y'_1, y'_2)$$
3. **Margin Monotonicity (Dilation Inclusion):**
   $$\forall S, m_1, m_2, y_1, y_2.\; 0 \le m_1 \le m_2 \implies \text{Interval}(S(m_1), y_1, y_2) \subseteq \text{Interval}(S(m_2), y_1, y_2)$$
4. **Margin-Box Clipping Invariant:**
   Per CSS Shapes L1 § 3.2: *"The shape is clipped to the float's margin box."* In `ShapeOutsideInfo::GetExcludedInterval`, any interval returned by `Shape::GetExcludedInterval` is clamped to the float's logical margin box $[0, \text{margin\_box\_inline\_size}]$.

### Edge Cases & Blink Divergences
1.