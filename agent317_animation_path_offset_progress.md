**AUDIT REPORT: Blink Motion Path Offset Progress Computation**
**Auditor:** Agent 317
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/style/ offset_*` & `platform/graphics/path.cc`)
**Subject:** Mathematical and Algorithmic Determination of Progress Along an `offset-path`

---

### 1. Executive Summary
In the Blink rendering engine, computing the precise position and rotation of an element along a CSS Motion Path (`offset-path`) requires translating a CSS `<length-percentage>` (`offset-distance`) into a normalized scalar progress value, and subsequently mapping that value to a 2D Cartesian coordinate (`gfx::PointF`) and a tangent angle (`float`) in layout space. This audit details the exact computation pipeline from style resolution to Skia geometry evaluation.

---

### 2. Phase I: Path Instantiation & Total Length Calculation
Before progress can be computed, Blink must construct the geometric path in the local coordinate space and determine its total arc length ($L_{\text{total}}$).

1. **Path Generation:** 
   Depending on the `offset-path` definition (`path()`, `ray()`, `<basic-shape>`, or `coord-box`), Blink generates a `blink::Path` object (a wrapper around `SkPath`).
2. **Total Length ($L_{\text{total}}$) Extraction:**
   Blink calls `Path::length()`, which invokes `SkPathMeasure(sk_path, force_closed=false).getLength()`. 
   * *Note:* Skia approximates Bezier curves using iterative subdivision (chebyshev/gauss quadrature or flattening tolerances) to compute the scalar arc length in CSS pixels.

---

### 3. Phase II: Resolving `offset-distance` to Raw Length
The `offset-distance` property is stored as a `blink::Length` object (which may be `Fixed`, `Percent`, or `Calculated`). 

During `OffsetPathOperation` evaluation (typically within `ComputedStyle::ApplyMotionPathTransform`), the used distance $D_{\text{raw}}$ is resolved against $L_{\text{total}}$:

$$D_{\text{raw}} = \text{FloatValueForLength}(\text{offset-distance}, L_{\text{total}})$$

* If `offset-distance` is a **percentage** $P$:
  $$D_{\text{raw}} = \left(\frac{P}{100}\right) \times L_{\text{total}}$$
* If `offset-distance` is a **pixel length** $X$:
  $$D_{\text{raw}} = X$$
* If `offset-distance` is a **`calc()`** expression, Blink resolves percentages against $L_{\text{total}}$ and combines them with absolute pixel values.

---

### 4. Phase III: Boundary Clamping & Closed-Loop Wrapping
Once $D_{\text{raw}}$ is computed, Blink must clamp or wrap the value based on the topological state of the path (Open vs. Closed) to find the effective distance $D_{\text{eff}}$.

#### Case A: Degenerate Path ($L_{\text{total}} == 0$)
If the path has zero length (e.g., `path("M 10 10 Z")` or an empty path):
$$D_{\text{eff}} = 0$$

#### Case B: Open Path (`IsClosed() == false`)
For paths that do not end with a `closepath` command (`Z` or `z`), progress cannot exceed the physical endpoints of the path. Blink clamps the value:
$$D_{\text{eff}} = \text{clamp}(D_{\text{raw}}, 0, L_{\text{total}})$$
*(i.e., $\max(0, \min(D_{\text{raw}}, L_{\text{total}}))$)*

#### Case C: Closed Loop Path (`IsClosed() == true`)
For closed paths (including basic shapes like `circle()` or SVG paths ending in `Z`), the distance wraps infinitely around the perimeter using a Euclidean modulo operation:

$$D_{\text{eff}} = \text{fmod}(D_{\text{raw}}, L_{\text{total}})$$

If $D_{\text{eff}} < 0$ (which occurs in C++ `std::fmod` when $D_{\text{raw}}$ is negative), Blink normalizes it to a positive offset:
$$D_{\text{eff}} = D_{\text{eff}} + L_{\text{total}}$$

*(Thus, $-10\%$ on a closed path correctly resolves to $90\%$ of $L_{\text{total}}$).*

*Normalized Progress Scalar ($t$):* 
While Skia operates on $D_{\text{eff}}$ directly, the conceptual CSS progress $t \in [0, 1]$ is defined as:
$$t = \frac{D_{\text{eff}}}{L_{\text{total}}}$$

---

### 5. Phase IV: Multi-Segment Traversal & Point/Tangent Extraction
An `offset-path` may consist of multiple disconnected sub-paths (via multiple `M` commands). Blink delegates the final evaluation to `Path::PointAndNormalAtLength(float length)`.

Under the hood, Blink uses `SkPathMeasure` to iterate over the contours:

1. **Contour Iteration:**
   `SkPathMeasure` measures one continuous contour at a time. Blink loops through contours, subtracting the current contour's length ($L_{\text{contour}}$) from $D_{\text{eff}}$ until it finds the specific contour where $D_{\text{eff}} \le L_{\text{contour}}$.
   ```cpp
   // Conceptual Blink/Skia traversal logic
   SkPathMeasure measure(path, false);
   do {
     float contour_length = measure.getLength();
     if (effective_distance <= contour_length) {
       measure.getPosTan(effective_distance, &position, &tangent);
       break;
     }
     effective_distance -= contour_length;
   } while (measure.nextContour());
   ```
2. **Spline Evaluation (`getPosTan`):**
   Once the target contour and remaining local distance are isolated, Skia maps the arc-length distance back to the parametric $t$-value of the specific line, quadratic, conic, or cubic Bezier segment using binary search over a precomputed arc-length lookup table (`SkContourMeasure::SegTo`).
3. **Output Generation:**
   * **Position ($P_x, P_y$):** The exact point on the curve at $D_{\text{eff}}$.
   * **Tangent ($T_x, T_y$):** The normalized derivative vector at that point.
   * **Angle ($\theta$):** Blink converts the tangent vector to degrees for `offset-rotate: auto`:
     $$\theta = \text{atan2}(T_y, T_x) \times \left(\frac{180}{\pi}\right)$$

---

### 6. Special Case: `ray()` Paths
When `offset-path: ray()` is used, the path is mathematically infinite, meaning $L_{\text{total}}$ is not inherently defined by geometry.
* Blink first computes the **containing block intersection**.
* $L_{\text{total}}$ is dynamically defined as the distance from the ray's origin (`offset-position`) to the edge of the containing box (determined by the `ray()` size keyword: `closest-side`, `farthest-corner`, etc.).
* Because a ray is an **Open Path**, wait—per the CSS Motion Path specification, **rays are un-clamped**. Blink overrides the Open Path clamping rule for `ray()`, allowing $D_{\text{eff}}$ to remain negative or exceed $L_{\text{total}}$ so elements can travel past the containing block boundaries.

---

### 7. Audit Conclusion
Blink’s offset progress computation strictly adheres to the W3C Motion Path Module Level 1 specification. By deferring arc-length parameterization to `SkPathMeasure` and handling topological wrapping (`fmod`) at the Blink style/layout boundary, the engine maintains sub-pixel accuracy and consistent frame-to-frame interpolation during compositor-driven animations. 

*End of Audit — Agent 317.*