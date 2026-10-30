Here is the comprehensive architectural audit and formalization of Chromium’s Blink transform coordinate mapping engine against the W3C CSS Transforms Module Level 1 specification.

---

### 1. Core Data Structures in Blink Transforms

In Chromium’s Blink rendering engine, coordinate mapping across layout boundaries and transformed stacking contexts is governed by three primary structures located in `third_party/blink/renderer/platform/transforms/` and `core/layout/`.

```
+-------------------------------------------------------------------+
|                        TransformState                             |
|  - accumulated_transform_: std::unique_ptr<TransformationMatrix>  |
|  - accumulated_offset_: PhysicalOffset (Fast-path 2D translation) |
|  - last_planar_point_ / last_planar_quad_: FloatPoint / FloatQuad |
|  - direction_: kApplyTransformDirection | kUnapply...             |
+-------------------------------------------------------------------+
                                 |
                                 | Delegates 4x4 / 3x2 math
                                 v
+-------------------------------------------------------------------+
|                     TransformationMatrix                          |
|  - matrix_[4][4]: Double-precision column-major 4x4 matrix        |
|  - (Affine 2D subset uses indices: m11, m12, m21, m22, m41, m42)  |
|  - MapPoint(), MapQuad(), MapRect(), Inverse(), Multiply()        |
+-------------------------------------------------------------------+
                                 ^
                                 | Parameterizes local origin
+-------------------------------------------------------------------+
|                       TransformOrigin                             |
|  - x_: Length (Fixed, Percent, Calculated)                        |
|  - y_: Length (Fixed, Percent, Calculated)                        |
|  - z_: float  (LayoutUnit/float resolved in 3D space)             |
+-------------------------------------------------------------------+
```

#### `TransformationMatrix` (`platform/transforms/transformation_matrix.h`)
While CSS Transforms Level 1 specifies 2D transforms using a $3 \times 3$ homogeneous matrix, Blink unifies 2D and 3D transforms inside a column-major $4 \times 4$ `double` matrix (`gfx::Transform` / `TransformationMatrix`). 
For 2D affine operations, the active components are mapped as:
*   `m11` ($a$), `m12` ($b$), `m21` ($c$), `m22` ($d$) — representing the $2 \times 2$ linear transformation (scale, rotation, skew).
*   `m41` ($e$ or $t_x$), `m42` ($f$ or $t_y$) — representing the 2D translation vector.
*   `m33` = 1.0, `m44` = 1.0, with all other 3D/perspective elements set to 0.0.
Using IEEE 754 `double` precision internally mitigates intermediate accumulation error before clamping back to `float` (` gfx::PointF` / `gfx::QuadF`) during geometry mapping.

#### `TransformOrigin` (`core/style/transform_origin.h`)
Encapsulates the raw CSS `transform-origin` property values as a tuple `(Length x, Length y, float z)`. During layout/paint (`ComputedStyle::ApplyTransform`), percentages in `x` and `y` are resolved against the target element's reference box (typically the `border-box` for standard HTML elements, or `fill-box`/`view-box` for SVG) to yield a concrete physical offset $(O_x, O_y, O_z)$ relative to the box's top-left corner.

#### `TransformState` (`core/layout/geometry/transform_state.h`)
Tracks the coordinate space state as Blink traverses the `LayoutObject` tree (e.g., via `MapLocalToAncestor` or `MapAncestorToLocal`).
*   **Directionality**: Encodes `TransformDirection` (`kApplyTransformDirection` for local-to-ancestor, `kUnapplyInverseTransformDirection` for ancestor-to-local).
*   **Fast-Path Optimization**: Maintains a `PhysicalOffset accumulated_offset_`. If traversal only encounters simple layout offsets (margins, top/left positioning, scroll offsets), Blink avoids allocating a heap-backed `TransformationMatrix` and simply accumulates 2D fixed-point `LayoutUnit` offsets. Once a non-trivial CSS transform is encountered, it flushes the offset into `accumulated_transform_` and switches to matrix multiplication mode.

---

### 2. 2D Affine Transform Application

Per **W3C CSS Transforms Module Level 1 (§ 6 The Transform Rendering Model)**, the local transformation matrix $C$ (Current Transformation Matrix) is computed by translating the coordinate space to the resolved `transform-origin`, applying the listed transform functions $M_1, M_2, \dots, M_n$ in left-to-right order, and translating the origin back.

#### Mathematical Formulation
Let the resolved transform origin be $\mathbf{O} = (O_x, O_y)^T$. In 2D homogeneous coordinates:

$$T(\mathbf{O}) = \begin{bmatrix} 1 & 0 & O_x \\ 0 & 1 & O_y \\ 0 & 0 & 1 \end{bmatrix}, \quad T(-\mathbf{O}) = \begin{bmatrix} 1 & 0 & -O_x \\ 0 & 1 & -O_y \\ 0 & 0 & 1 \end{bmatrix}$$

Let the composite CSS `transform` matrix be $M = M_1 \cdot M_2 \cdots M_n$:

$$M = \begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix}$$

where the primitive matrices are defined as:
*   **Translation**: $\text{translate}(t_x, t_y) \implies a=1, d=1, e=t_x, f=t_y, b=c=0$.
*   **Scale**: $\text{scale}(s_x, s_y) \implies a=s_x, d=s_y, b=c=e=f=0$.
*   **Rotation**: $\text{rotate}(\theta) \implies a=\cos\theta, b=\sin\theta, c=-\sin\theta, d=\cos\theta, e=f=0$.
*   **Skew**: $\text{skew}(\alpha, \beta) \implies a=1, b=\tan\beta, c=\tan\alpha, d=1, e=f=0$.

The complete local transformation matrix $C$ is:

$$C = T(\mathbf{O}) \cdot M \cdot T(-\mathbf{O})$$

Expanding this product algebraically:

$$C = \begin{bmatrix} 1 & 0 & O_x \\ 0 & 1 & O_y \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} 1 & 0 & -O_x \\ 0 & 1 & -O_y \\ 0 & 0 & 1 \end{bmatrix}$$

$$C = \begin{bmatrix} 1 & 0 & O_x \\ 0 & 1 & O_y \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} a & c & e - aO_x - cO_y \\ b & d & f - bO_x - dO_y \\ 0 & 0 & 1 \end{bmatrix}$$

$$C = \begin{bmatrix} a & c & e + O_x(1 - a) - cO_y \\ b & d & f + O_y(1 - d) - bO_x \\ 0 & 0 & 1 \end{bmatrix}$$

For any local physical point $\mathbf{p} = (x, y, 1)^T$, its mapped point $\mathbf{p}' = (x', y', 1)^T = C\mathbf{p}$ is:

$$x' = ax + cy + e + O_x(1 - a) - cO_y = a(x - O_x) + c(y - O_y) + e + O_x$$

$$y' = bx + dy + f + O_y(1 - d) - bO_x = b(x - O_x) + d(y - O_y) + f + O_y$$

#### Blink Implementation (`ComputedStyle::ApplyTransform`)
In Blink, `TransformationMatrix::Translate(Ox, Oy)` post-multiplies the current matrix:
1. Initialize `TransformationMatrix matrix;` (Identity).
2. If `apply_transform_origin` is true: `matrix.Translate3d(origin_x, origin_y, origin_z);` ($T(\mathbf{O})$).
3. Iterate over `TransformOperations` and post-multiply each operation: `op->Apply(box_size, matrix);` ($T(\mathbf{O}) \cdot M$).
4. If `apply_transform_origin` is true: `matrix.Translate3d(-origin_x, -origin_y, -origin_z);` ($T(\mathbf{O}) \cdot M \cdot T(-\mathbf{O})$).

---

### 3. Invertibility Check and Bounding Box Mapping

#### Invertibility Check
To map coordinates from an ancestor space down to a local space (e.g., hit-testing via `kUnapplyInverseTransformDirection`), Blink must invert $C$.

For a 2D affine matrix $C$, the determinant is invariant under similarity transformations ($T(\mathbf{O})$ and $T(-\mathbf{O})$ cancel out in the determinant product):

$$\det(C) = \det(T(\mathbf{O})) \cdot \det(M) \cdot \det(T(-\mathbf{O})) = 1 \cdot (ad - bc) \cdot 1 = ad - bc$$

*   **Exact Math**: $C$ is invertible iff $\det(C) = ad - bc \neq 0$.
*   **Blink Implementation**: In `TransformationMatrix::IsInvertible()` and `Inverse()`, Blink computes the determinant in `double` precision. For the 2D affine fast-path:
    ```cpp
    double det = m11() * m22() - m12() * m21();
    if (!std::isfinite(det) || std::abs(det) < kDeterminantThreshold)
        return false;
    ```
    where `kDeterminantThreshold` is bounded by `std::numeric_limits<double>::epsilon()` (or `1e-14` depending on the `gfx::Transform` path). If non-invertible (e.g., `scale(0)` or `skewX(90deg)`), hit-testing and ancestor-to-local mapping abort and return an empty quad/point, matching **CSS Transforms Level 1 § 6**: *"If a transform function causes the current transformation matrix of an object to be non-invertible, the object and its content do not get displayed."*

The analytical inverse $C^{-1}$ is:

$$C^{-1} = T(\mathbf{O}) \cdot M^{-1} \cdot T(-\mathbf{O}) = \frac{1}{ad - bc} \begin{bmatrix} d & -c & c(f + O_y) - d(e + O_x) + (ad-bc)O_x \\ -b & a & b(e + O_x) - a(f + O_y) + (ad-bc)O_y \\ 0 & 0 & ad - bc \end{bmatrix}$$

#### Mapping Physical Bounding Boxes (`MapRect` / `MapQuad`)
An Axis-Aligned Bounding Box (AABB) $R = [x_{\min}, x_{\max}] \times [y_{\min}, y_{\max}]$ generally loses axis alignment under rotation or skew. Blink maps $R$ to its enclosing transformed AABB $R'$ (`TransformationMatrix::MapRect`) as follows:

1. **Extract Corners**: Decompose $R$ into a `FloatQuad` consisting of 4 vertices:
   $$\mathbf{v}_1 = (x_{\min}, y_{\min}), \quad \mathbf{v}_2 = (x_{\max}, y_{\min}), \quad \mathbf{v}_3 = (x_{\max}, y_{\max}), \quad \mathbf{v}_4 = (x_{\min}, y_{\max})$$
2. **Transform Vertices**: Apply $\mathbf{v}'_i = C \mathbf{v}_i$ for $i \in \{1, 2, 3, 4\}$.
3. **Compute Enclosing AABB**: Find the extrema of the mapped vertices (`FloatQuad::BoundingBox()`):
   $$x'_{\min} = \min_{i=1..4} (\mathbf{v}'_i)_x, \quad x'_{\max} = \max_{i=1..4} (\mathbf{v}'_i)_x$$
   $$y'_{\min} = \min_{i=1..4} (\mathbf{v}'_i)_y, \quad y'_{\max} = \max_{i=1..4} (\mathbf{v}'_i)_y$$

---

### 4. Mathematical Invariants, Edge Cases, and Divergences

#### Core Mathematical Invariants
1. **Identity Transform Neutrality**: If $M = I_3$, then for any origin $\mathbf{O}$, $C = T(\mathbf{O}) \cdot I_3 \cdot T(-\mathbf{O}) = I_3$, and $\forall \mathbf{p}, C\mathbf{p} = \mathbf{p}$.
2. **Origin-Shift Homomorphism (Conjugation Composition)**: Applying a sequence of matrices $M_1, M_2$ with respect to the same origin $\mathbf{O}$ is equivalent to conjugating their product:
   $$\left(T(\mathbf{O}) M_1 T(-\mathbf{O})\right) \cdot \left(T(\mathbf{O}) M_2 T(-\mathbf{O})\right) = T(\mathbf{O}) (M_1 M_2) T(-\mathbf{O})$$
3. **Pure Translation Origin-Invariance**: If $M = \text{translate}(t_x, t_y)$ (so $a=1, d=1, b=0, c=0$), then $C = M$ regardless of $\mathbf{O}$:
   $$e' = e + O_x(1 - 1) - 0\cdot O_y = e, \quad f' = f + O_y(1 - 1) - 0\cdot O_x = f$$
4. **Convexity & Bounding Box Containment**: Because affine transformations preserve collinearity and convexity ($C(\lambda \mathbf{p} + (1-\lambda)\mathbf{q}) = \lambda C\mathbf{p} + (1-\lambda)C\mathbf{q}$ for $\lambda \in [0, 1]$), any point $\mathbf{p} \in R$ can be written as a convex combination of the 4 corners $\mathbf{v}_1, \dots, \mathbf{v}_4$. Therefore, $C\mathbf{p}$ is a convex combination of $\mathbf{v}'_1, \dots, \mathbf{v}'_4$, guaranteeing that $C\mathbf{p}$ lies strictly within the enclosing AABB $R'$.

#### Edge Cases & Blink vs. W3C Divergences

| Category | W3C CSS Transforms Level 1 | Chromium Blink Behavior