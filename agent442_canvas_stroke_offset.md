**AUDIT LOG: AGENT 442**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/modules/canvas/canvas2d/`)
**SUBJECT:** Canvas 2D Stroke Offset & Half-Width Derivation

---

### 1. EXECUTIVE SUMMARY
In Blink’s Canvas 2D context, rendering a stroke is not a simple pixel-plotting operation; it is a geometric expansion of a 1D mathematical path into a 2D fillable polygon (or SDF geometry) executed by the underlying Skia graphics engine. 

The **stroke half-width ($w_{half}$)** is the fundamental scalar used to offset the base path along its local normal vectors. Misalignment of this offset relative to the physical pixel grid is the primary cause of the notorious Canvas "blurry 1px line" artifact.

---

### 2. MATHEMATICAL DERIVATION OF STROKE HALF-WIDTH

In the HTML5 Canvas specification, a path has zero width. When `ctx.stroke()` is called, the path is centered on the mathematical coordinates provided. 

#### 2.1 Base Scalar Derivation
Given a user-defined `lineWidth` ($W$), the base offset distance from the path's centerline to its outer and inner edges is simply the half-width ($r$):

$$r = \frac{W}{2}$$

#### 2.2 Vector Normal Extrusion
For a given path segment defined by a parametric curve $P(t) = (x(t), y(t))$, the tangent vector $T(t)$ is derived via the first derivative:

$$T(t) = P'(t) = (x'(t), y'(t))$$

The unit normal vector $N(t)$, perpendicular to the tangent, is calculated as:

$$N(t) = \frac{(-y'(t), x'(t))}{\sqrt{x'(t)^2 + y'(t)^2}}$$

The inner ($P_{inner}$) and outer ($P_{outer}$) boundaries of the stroke are derived by offsetting $P(t)$ by the half-width along the normal vector:

$$P_{outer}(t) = P(t) + r \cdot N(t)$$
$$P_{inner}(t) = P(t) - r \cdot N(t)$$

---

### 3. BLINK / SKIA IMPLEMENTATION PIPELINE

In Blink, `BaseRenderingContext2D` passes the stroke state to `cc::PaintFlags`, which ultimately translates to Skia’s `SkPaint` and `SkStrokeRec`.

#### 3.1 CTM (Current Transformation Matrix) Application
Blink does not simply divide `lineWidth` by 2 in device space. The half-width is derived in **user space** and then transformed by the Current Transformation Matrix ($M$), which includes CSS scaling, `devicePixelRatio` (DPR), and canvas context transforms (`scale`, `rotate`, `transform`).

Let $M_{2\times2}$ be the upper-left linear transformation submatrix of the CTM. The transformed normal offset vector $V_{offset}$ in device space is:

$$V_{offset} = M_{2\times2} \cdot (r \cdot N(t))$$

*Audit Note:* If the canvas undergoes non-uniform scaling (e.g., `ctx.scale(2, 1)`), the effective half-width in device pixels becomes elliptical, varying based on the angle of the normal vector $N(t)$.

#### 3.2 Join and Cap Perturbations
At path vertices (joins) and endpoints (caps), the simple normal offset fails, requiring geometric bridging using the half-width $r$:
*   **Butt Cap:** Terminates exactly at $P(t_{end})$. Offset is $0$ along the tangent, $\pm r$ along the normal.
*   **Square Cap:** Extrudes along the tangent vector by $r$: $P_{cap} = P(t_{end}) + r \cdot \hat{T}(t) \pm r \cdot N(t)$.
*   **Round Cap/Join:** Arcs of radius $r$ centered at the vertex.
*   **Miter Join:** The outer offset edges are extended until they intersect. The distance from the vertex to the intersection (Miter Length, $L$) is derived using the half-width and the angle $\theta$ between segments:
    $$L = \frac{r}{\sin(\frac{\theta}{2})}$$
    *(If $L / r > \text{miterLimit}$, Skia falls back to a Bevel join).*

---

### 4. THE SUB-PIXEL OFFSET ANOMALY (AUDIT FINDING)

A critical point of failure in developer implementations of Blink Canvas involves the interaction between integer coordinates and the half-width derivation.

*   **The Grid:** Physical device pixels are indexed by integers, with their centers located at half-integer coordinates (e.g., $(0.5, 0.5)$).
*   **The Scenario:** A developer draws a vertical line at $x = 10$ with `lineWidth = 1.0`.
*   **The Derivation:** 
    *   $r = 1.0 / 2 = 0.5$
    *   $P_{inner} = 10 - 0.5 = 9.5$
    *   $P_{outer} = 10 + 0.5 = 10.5$
*   **The Rasterization Result:** The stroke spans from $9.5$ to $10.5$. It covers 50% of pixel column $9$ (which spans $9.0$ to $10.0$) and 50% of pixel column $10$ (which spans $10.0$ to $11.0$).
*   **Skia Anti-Aliasing (AA):** Skia's coverage-based AA calculates an alpha value of $0.5$ for both pixels. The result is a 2px wide line at 50% opacity, rather than a crisp 1px line.

**Resolution Protocol:** To achieve pixel-aligned edges where $P_{inner}$ and $P_{outer}$ land on integer boundaries, the base path must be offset by $(r \pmod 1)$ if $W$ is odd, typically $0.5$ in standard DPI.

---

### 5. GPU ACCELERATION & HAIRLINES (GANESH / GRAPHITE)

When Blink offloads canvas rendering to the GPU via Skia's Ganesh or Graphite backends, half-width derivation undergoes a branch check in `SkStrokeRec::getStyle()`:

1.  **Hairline Mode ($W = 0$ or $W_{device} \le 1\text{px}$ under certain AA flags):** 
    The geometric half-width derivation is bypassed. The GPU rasterizer renders a constant 1-device-pixel wide path regardless of the CTM scale, using coverage modulation for sub-pixel widths.
2.  **Standard Stroke ($r > 0.5\text{px}$):** 
    Tessellation shaders compute the $P(t) \pm r \cdot N(t)$ quad expansions directly on the GPU, passing the half-width as a uniform or vertex attribute to construct the geometry dynamically.

**END OF AUDIT - AGENT 442**