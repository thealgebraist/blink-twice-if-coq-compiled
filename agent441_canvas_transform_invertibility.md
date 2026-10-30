**AUDIT LOG: AGENT 441**
**SUBJECT:** Blink Canvas 2D/3D Transform Invertibility
**FOCUS:** Determinant Non-Zero Invertibility & Numerical Stability

---

### 1. Mathematical Foundation in Blink
In the Chromium/Blink rendering engine, the HTML5 Canvas 2D context relies on an underlying transformation matrix (historically `AffineTransform`, increasingly unified with `gfx::Transform` and Skia's `SkMatrix`) to map coordinates from the canvas user space to the device space. 

For a standard 2D affine transformation matrix $M$:

$$M = \begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix}$$

Where:
*   $a, d$ represent scaling.
*   $b, c$ represent skewing/shearing.
*   $e, f$ represent translation.

#### The Invertibility Condition
To map device coordinates back to user coordinates (essential for hit-testing via `isPointInPath`, `isPointInStroke`, and inverse matrix retrieval via `getTransform().invertSelf()`), the matrix $M$ must be invertible. 

A square matrix is invertible if and only if its determinant is non-zero ($\det(M) \neq 0$). Because the bottom row of a 2D affine matrix is fixed at $[0, 0, 1]$, the determinant simplifies to the $2 \times 2$ linear transformation submatrix:

$$\det(M) = ad - bc$$

The inverse matrix $M^{-1}$ is computed as:

$$M^{-1} = \frac{1}{\det(M)} \begin{bmatrix} d & -c & cf - de \\ -b & a & be - af \\ 0 & 0 & \det(M) \end{bmatrix}$$

If $\det(M) = 0$, the transformation collapses the 2D plane into a 1D line or a 0D point (a **singular** or **degenerate** matrix). Division by zero occurs, making the inverse mathematically undefined.

---

### 2. Blink Implementation & Floating-Point Realities
In C++ (`third_party/blink/renderer/modules/canvas/canvas2d/` and `ui/gfx/geometry/`), checking for strict inequality (`det != 0.0`) is insufficient due to IEEE 754 floating-point limitations. 

Agent 441 audit highlights three specific areas of concern regarding non-zero determinant checks in Blink:

#### A. Subnormal Numbers and Underflow/Overflow
If $a, b, c, d$ are extremely small (approaching `FLT_MIN` or `DBL_MIN`), $\det(M)$ may underflow to `0.0`, rendering a theoretically invertible matrix non-invertible. Conversely, if $\det(M)$ is a non-zero subnormal number (e.g., $10^{-320}$), dividing by $\det(M)$ to compute $M^{-1}$ will result in floating-point overflow (`Infinity`), corrupting the Skia Path or Canvas state.

**Blink's Mitigation:**
Blink and Skia do not just check `det != 0`. They check if the determinant is **finite** and **above a specific epsilon threshold**, or they verify that the resulting inverted matrix elements remain finite (`std::isfinite`).
*   *In `AffineTransform::IsInvertible()`*: The determinant is calculated in `double` precision even if the matrix stores `float` values, preventing premature underflow/overflow during the $ad - bc$ multiplication.

#### B. State Corruption on Non-Invertible Transforms
According to the **WHATWG HTML Living Standard**, if a canvas context's transformation matrix becomes non-invertible (e.g., via `ctx.scale(0, 0)` or `ctx.transform(0, 0, 0, 0, 0, 0)`):
1.  Drawing operations (`fill()`, `stroke()`, `drawImage()`) must silently abort.
2.  Path creation methods (`lineTo()`, `rect()`) must either not record points or fail silently when rendered, because the current transformation matrix (CTM) cannot map the path consistently to the existing subpaths if the CTM changed mid-path.

**Blink Audit Finding:**
Blink tracks this state explicitly via `CanvasRenderingContext2DState::IsTransformInvertible()`. 
*   When a mutating method (`scale`, `rotate`, `transform`, `setTransform`) is called, Blink updates the CTM and immediately evaluates $\det(M)$.
*   If $\det(M) == 0$ (or is non-finite), an internal flag `is_transform_invertible_` is set to `false`.
*   All subsequent path-building and rendering calls early-out by checking `if (!GetState().IsTransformInvertible()) return;` before passing data to the Skia backend (`cc::PaintCanvas`). This prevents passing `NaN` or `Infinity` coordinates to the GPU rasterizer, which could otherwise cause renderer crashes or GPU hangs.

#### C. `DOMMatrix` vs. Internal CTM Discrepancies
When a developer calls `ctx.getTransform()`, Blink returns a `DOMMatrix` object. 
*   `DOMMatrix` is a 4x4 3D matrix specification, even for a 2D canvas.
*   If `invertSelf()` is called on this `DOMMatrix`, it uses a 4x4 determinant calculation (Laplace expansion or Gaussian elimination).
*   **Audit Note:** Ensure parity between `AffineTransform::IsInvertible()` (2D) and `TransformationMatrix::IsInvertible()` (3D). A matrix might be deemed non-invertible by Skia's `SkMatrix::invert()` (which uses `float` precision and a specific `SK_ScalarNearlyZero` threshold) while `DOMMatrix` (using `double` precision) successfully inverts it.

---

### 3. Security & Stability Vectors (Audit Checklist)

As Agent 441, the following edge cases must be continuously fuzz-tested in Blink's Canvas implementation:

1.  **The "Almost Zero" Scale Attack:** 
    *   *Vector:* `ctx.scale(1e-200, 1e-200);`
    *   *Risk:* Individual components are valid `double` values, but $ad - bc = 10^{-400}$, which underflows to `0.0` in IEEE 754 double-precision. Blink must catch this at the determinant level, not by checking if scale parameters $x == 0$ or $y == 0$ at the API boundary.
2.  **Shear Cancellation:**
    *   *Vector:* `ctx.setTransform(2, 4, 1, 2, 0, 0);`
    *   *Risk:* No zeros are passed into the API, yet $ad - bc = (2)(2) - (1)(4) = 0$. The matrix collapses 2D space onto the line $y = 2x$. The determinant check is the *only* defense against this singularity.
3.  **NaN Propagation via `setTransform`:**
    *   *Vector:* Passing `Infinity` or `NaN` into matrix mutators (where WebIDL allows `unrestricted double`).
    *   *Risk:* In IEEE 754, `NaN != 0` evaluates to `true` in older compilers or naive bitwise checks, whereas `!(std::abs(det) > 0.0)` safely catches both `0.0` and `NaN`. Blink must strictly use `std::isfinite(det) && det != 0` (or equivalent epsilon checks).

### 4. Conclusion
Blink's Canvas transform invertibility relies strictly on the algebraic condition $ad - bc \neq 0$, bounded by IEEE 754 `double` precision limits and guarded by `std::isfinite`. The `is_transform_invertible_` state flag acts as a circuit breaker, isolating the Skia rendering pipeline from singular matrices and preventing division-by-zero vulnerabilities during inverse coordinate mapping. 

**STATUS:** *Audit Complete. Determinant validation logic is sound, contingent on maintaining `double`-precision intermediate calculations prior to Skia `float` downcast.*