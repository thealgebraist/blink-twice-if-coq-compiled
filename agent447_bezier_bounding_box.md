**AUDIT REPORT: BLINK RENDERING ENGINE**
**Agent:** 447
**Component:** Geometry / Rasterization Pipeline (`blink::Path`, `SkPath`, `cc::MathUtil`)
**Subject:** Bézier Curve Bounding Envelope & Convex Hull Containment

---

### 1. Executive Summary
Audit of the Blink rendering engine’s curve evaluation confirms that **Convex Hull Containment** is the primary geometric invariant used to optimize bounding box calculations, culling, and hit-testing for Quadratic and Cubic Bézier curves. By leveraging the mathematical property that a Bézier curve lies entirely within the convex hull of its control points, Blink (via Skia and CC) avoids expensive analytical root-finding during preliminary layout and paint phases.

---

### 2. Mathematical Foundation: The Convex Hull Property
A Bézier curve $B(t)$ of degree $n$ with control points $P_0, P_1, \dots, P_n$ is defined as:

$$B(t) = \sum_{i=0}^{n} b_{i,n}(t) P_i \quad \text{for } t \in [0, 1]$$

Where $b_{i,n}(t)$ are the Bernstein basis polynomials:

$$b_{i,n}(t) = \binom{n}{i} t^i (1-t)^{n-i}$$

**Audit Verification of Containment:**
1. **Non-negativity:** For all $t \in [0, 1]$, $t \ge 0$ and $(1-t) \ge 0$, therefore $b_{i,n}(t) \ge 0$.
2. **Partition of Unity:** By the Binomial Theorem, $\sum_{i=0}^{n} b_{i,n}(t) = (t + (1-t))^n = 1^n = 1$.

Because $B(t)$ is a convex combination of $P_i$, the curve is mathematically guaranteed to never exit the convex polygon formed by its control points.

---

### 3. Blink Implementation: Fast vs. Tight Envelopes

In the Chromium/Blink pipeline, bounding envelopes are computed at two distinct levels of precision depending on the subsystem requirement:

#### A. The Fast Envelope (Control Point Bounds)
* **Mechanism:** Computes the Axis-Aligned Bounding Box (AABB) of the convex hull.
* **Formula:** 
  $$\text{Min}_{x,y} = \min(P_0, P_1, P_2, P_3)$$
  $$\text{Max}_{x,y} = \max(P_0, P_1, P_2, P_3)$$
* **Audit Findings:** 
  * **Performance:** $O(1)$ using SIMD `minps`/`maxps` instructions. Zero division or square root operations.
  * **Usage:** Used in `SkPath::getBounds()`, layer tree invalidation, and coarse viewport culling.
  * **Trade-off:** Results in a *conservative* (loose) bounding envelope. If $P_1$ or $P_2$ lie far from the curve's apex, the AABB encompasses empty space, potentially triggering unnecessary raster tile allocations.

#### B. The Tight Envelope (Derivative Root-Finding)
* **Mechanism:** Analytically finds the local extrema of the curve to shrink the envelope inside the convex hull.
* **Formula:** Solves $B'(t) = 0$ for $t \in (0, 1)$ independently for X and Y axes. For a cubic curve, this requires solving the quadratic equation:
  $$At^2 + Bt + C = 0$$
  where:
  $$A = -P_0 + 3P_1 - 3P_2 + P_3$$
  $$B = 2(P_0 - 2P_1 + P_2)$$
  $$C = -P_0 + P_1$$
* **Audit Findings:**
  * **Performance:** High computational overhead (requires floating-point division and `sqrt`).
  * **Usage:** Used in SVG `getBBox()` specifications, precise hit-testing (`LayoutSVGShape`), and `gfx::QuadF` tight bounds calculations.

---

### 4. Subdivision & Hull Convergence (De Casteljau's Algorithm)
When Blink requires high-precision intersection testing (e.g., cursor hit-testing on a stroked Bézier path) or curve flattening for GPU tessellation, the loose convex hull is insufficient. 

Instead of immediate analytical solving, the engine utilizes **Recursive Subdivision**:
1. Using De Casteljau's algorithm, the curve is split at $t = 0.5$ into two sub-curves.
2. Each sub-curve generates a new, smaller set of control points.
3. **Containment Audit:** The union of the new convex hulls is strictly contained within the parent convex hull, converging quadratically toward the true curve geometry.
4. **Flatness Criterion (Wang's Formula):** Subdivision halts when the distance of the interior control points from the baseline ($P_0 \to P_n$) falls below the sub-pixel tolerance threshold ($\epsilon$). At this point, the convex hull is treated as a simple line segment.

---

### 5. Vulnerability & Edge-Case Analysis

 As Agent 447, I have flagged the following edge cases in the current bounding envelope logic:

1. **Floating-Point Overflow on Extreme Control Points:**
   * *Issue:* In calculating the tight envelope, $B^2 - 4AC$ can overflow `float32` limits if CSS/SVG coordinates contain extreme values (e.g., `1e20`), causing `NaN` propagation in the bounding box.
   * *Mitigation:* Blink clamps path coordinates or promotes intermediate discriminant calculations to `double` (`float64`).
2. **Cusp and Inflection Point Miter Limits:**
   * *Issue:* While the *fill* of a Bézier curve is strictly contained within the convex hull, a *stroked* Bézier curve is not. If a cubic curve contains a sharp cusp, the stroke's miter join can project infinitely far outside the control point hull.
   * *Mitigation:* The bounding envelope must be inflated by `stroke_width * miter_limit` after hull calculation.
3. **Degenerate Hulls (Collinear Points):**
   * *Issue:* When $P_0, P_1, P_2, P_3$ are collinear, the convex hull has zero area (1D line). If $P_1$ or $P_2$ lie *outside* the segment $P_0P_3$ (a curve that folds back on itself), the fast AABB will still bound the fold correctly, as the curve cannot exceed its control points even in 1D.

### 6. Conclusion
**Status: COMPLIANT.** 
Blink's utilization of Convex Hull Containment is mathematically sound. The dual-tiered approach—using the convex hull AABB for rapid rejection and deferring derivative root-finding/subdivision to localized operations—maintains the 60/120fps rendering budget without sacrificing geometric integrity. 

*End of Audit — Agent 447.*