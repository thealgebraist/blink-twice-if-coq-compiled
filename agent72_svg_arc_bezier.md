### 1. Core Data Structures in Blink SVG Path Parsing

In Chromium's Blink rendering engine (`third_party/blink/renderer/core/svg/` and `third_party/blink/renderer/platform/graphics/`), SVG path data is parsed and decomposed into canonical drawing primitives before being handed off to Skia (`SkPath`).

#### `SVGPathParser` & `SVGPathNormalizer`
`SVGPathParser` operates as a pull-push state machine linking a `SVGPathSource` (e.g., `SVGPathStringSource` or `SVGPathByteStreamSource`) to a `SVGPathConsumer` (such as `SVGPathBuilder` or `SVGPathNormalizer`). 

When `SVGPathNormalizer::EmitSegment` encounters an `kPathSegArcAbs` or `kPathSegArcRel` segment, it first resolves relative coordinates against the current subpath point $(x_1, y_1)$, then invokes `DecomposeArcToCubic` to convert the SVG elliptical arc into a sequence of cubic Bézier segments (`kPathSegCurveToCubicAbs`).

```cpp
// Conceptual structure inside third_party/blink/renderer/core/svg/svg_path_parser.h
struct PathSegmentData {
  SVGPathSegType command;
  gfx::PointF target_point; // (x2, y2)
  gfx::PointF point1;       // (rx, ry) for arcs; (x1, y1) for curves
  gfx::PointF point2;       // (angle, 0) for arcs; (x2, y2) for curves
  bool arc_large;           // large-arc-flag (f_A)
  bool arc_sweep;           // sweep-flag (f_S)
};
```

#### `PathAppender` / `SVGPathConsumer`
The consumer interface exposes segment emission. During normalization, `EmitSegment` translates high-level commands into three primitive absolute operations: `MoveTo`, `LineTo`, `CurveToCubic`, and `ClosePath`.

#### `ArcParameterization` (Internal Representation)
While Blink converts arcs directly inside `SVGPathNormalizer::DecomposeArcToCubic` (or delegates to `SkPath::arcTo` in direct paths), the internal parameterization state transitions from **Endpoint Parameterization** to **Center Parameterization**:

```cpp
struct EndpointArc {
  gfx::PointF p1;        // Current point (x1, y1)
  gfx::PointF p2;        // Target point (x2, y2)
  float rx, ry;          // Radii
  float x_axis_rotation; // Phi in degrees
  bool large_arc_flag;   // f_A
  bool sweep_flag;       // f_S
};

struct CenterArc {
  gfx::PointF center;    // (cx, cy)
  float rx, ry;          // Scaled radii >= 0
  float phi;             // Rotation in radians
  float theta1;          // Start angle in radians
  float delta_theta;     // Sweep angle in radians
};
```

---

### 2. Elliptical Arc Conversion Pipeline (SVG 2 §9.5 / B.2)

The conversion strictly follows the SVG 2 Appendix B.2 ("Conversion from endpoint to center parameterization") before projecting unit-circle cubic Bézier approximations back into the transformed ellipse space.

#### Step 1: Degeneracy Checks and Radii Normalization
Given $P_1 = (x_1, y_1)$ and $P_2 = (x_2, y_2)$:
1. If $P_1 = P_2$, the arc is degenerate and omitted completely (no segments emitted).
2. If $r_x = 0$ or $r_y = 0$, the arc is treated as a straight line segment (`kPathSegLineToAbs` to $P_2$).
3. Take absolute values of radii: $r_x \leftarrow |r_x|$, $r_y \leftarrow |r_y|$.
4. Convert angle $\varphi_{\text{deg}}$ to radians: $\varphi = (\varphi_{\text{deg}} \bmod 360^\circ) \cdot \frac{\pi}{180}$.

#### Step 2: Transformation to the Unrotated Midpoint Frame
Compute the transformed midpoint $(x_1', y_1')$:
$$\begin{pmatrix} x_1' \\ y_1' \end{pmatrix} = \begin{pmatrix} \cos\varphi & \sin\varphi \\ -\sin\varphi & \cos\varphi \end{pmatrix} \begin{pmatrix} \frac{x_1 - x_2}{2} \\ \frac{y_1 - y_2}{2} \end{pmatrix}$$

#### Step 3: Radii Scaling (Ensuring Existence of Solution)
To guarantee the distance between endpoints can be bridged by an ellipse of radii $(r_x, r_y)$, compute the scale factor $\Lambda$:
$$\Lambda = \frac{x_1'^2}{r_x^2} + \frac{y_1'^2}{r_y^2}$$
If $\Lambda > 1$, the radii are too small. They are scaled uniformly by $\sqrt{\Lambda}$:
$$r_x \leftarrow \sqrt{\Lambda} \cdot r_x, \quad r_y \leftarrow \sqrt{\Lambda} \cdot r_y$$

#### Step 4: Computing the Center $(c_x, c_y)$
Compute the radical term for the transformed center $(c_x', c_y')$:
$$\text{num} = r_x^2 r_y^2 - r_x^2 y_1'^2 - r_y^2 x_1'^2, \quad \text{den} = r_x^2 y_1'^2 + r_y^2 x_1'^2$$
Note that after Step 3, $\frac{\text{num}}{\text{den}} = \frac{1}{\Lambda} - 1 \ge 0$. However, to guard against IEEE 754 floating-point inaccuracies when $\Lambda$ was scaled to $\approx 1$, Blink clamps the quotient to $0$:
$$k = \pm \sqrt{\max\left(0, \frac{r_x^2 r_y^2 - r_x^2 y_1'^2 - r_y^2 x_1'^2}{r_x^2 y_1'^2 + r_y^2 x_1'^2}\right)}$$
The sign is chosen positive if $f_A \neq f_S$, and negative if $f_A = f_S$. Then:
$$\begin{pmatrix} c_x' \\ c_y' \end{pmatrix} = k \begin{pmatrix} \frac{r_x y_1'}{r_y} \\ -\frac{r_y x_1'}{r_x} \end{pmatrix}$$
$$\begin{pmatrix} c_x \\ c_y \end{pmatrix} = \begin{pmatrix} \cos\varphi & -\sin\varphi \\ \sin\varphi & \cos\varphi \end{pmatrix} \begin{pmatrix} c_x' \\ c_y' \end{pmatrix} + \begin{pmatrix} \frac{x_1 + x_2}{2} \\ \frac{y_1 + y_2}{2} \end{pmatrix}$$

#### Step 5: Computing Angles $\theta_1$ and $\Delta\theta$
Define the angle between two vectors $\mathbf{u}, \mathbf{v}$ as $\angle(\mathbf{u}, \mathbf{v}) = \pm \arccos\left(\frac{\mathbf{u} \cdot \mathbf{v}}{\|\mathbf{u}\|\|\mathbf{v}\|}\right)$, where the sign is the sign of $(u_x v_y - u_y v_x)$. Let:
$$\mathbf{u} = \begin{pmatrix} 1 \\ 0 \end{pmatrix}, \quad \mathbf{v} = \begin{pmatrix} \frac{x_1' - c_x'}{r_x} \\ \frac{y_1' - c_y'}{r_y} \end{pmatrix}, \quad \mathbf{w} = \begin{pmatrix} \frac{-x_1' - c_x'}{r_x} \\ \frac{-y_1' - c_y'}{r_y} \end{pmatrix}$$
$$\theta_1 = \angle(\mathbf{u}, \mathbf{v}), \quad \Delta\theta = \angle(\mathbf{v}, \mathbf{w}) \bmod 2\pi$$
Adjust $\Delta\theta$ based on the sweep flag $f_S$:
- If $f_S = 0$ and $\Delta\theta > 0$, then $\Delta\theta \leftarrow \Delta\theta - 2\pi$.
- If $f_S = 1$ and $\Delta\theta < 0$, then $\Delta\theta \leftarrow \Delta\theta + 2\pi$.

#### Step 6: Splitting into Segments $\le \frac{\pi}{2}$ and Cubic Bézier Generation
To bound the radial approximation error, the sweep $\Delta\theta$ is subdivided into $N$ equal segments such that each segment sweeps an angle $\delta\theta$ with $|\delta\theta| \le \frac{\pi}{2}$:
$$N = \left\lceil \frac{|\Delta\theta|}{\pi / 2} \right\rceil, \quad \delta\theta = \frac{\Delta\theta}{N}$$
For segment $i \in \{0, \dots, N-1\}$, let $\alpha_1 = \theta_1 + i\delta\theta$ and $\alpha_2 = \alpha_1 + \delta\theta$. The tangent scale factor $\kappa$ (derived from matching the midpoint of the circular arc) is:
$$\kappa = \frac{4}{3} \tan\left(\frac{\delta\theta}{4}\right)$$
On the unit circle, the four control points $Q_0, Q_1, Q_2, Q_3$ are:
$$Q_0 = \begin{pmatrix} \cos\alpha_1 \\ \sin\alpha_1 \end{pmatrix}, \quad Q_1 = Q_0 + \kappa \begin{pmatrix} -\sin\alpha_1 \\ \cos\alpha_1 \end{pmatrix}$$
$$Q_3 = \begin{pmatrix} \cos\alpha_2 \\ \sin\alpha_2 \end{pmatrix}, \quad Q_2 = Q_3 - \kappa \begin{pmatrix} -\sin\alpha_2 \\ \cos\alpha_2 \end{pmatrix}$$
Each point $Q_j = (q_{jx}, q_{jy})$ is mapped back to the world coordinate space via the affine transformation $T$:
$$P_j = T(Q_j) = \begin{pmatrix} \cos\varphi & -\sin\varphi \\ \sin\varphi & \cos\varphi \end{pmatrix} \begin{pmatrix} r_x q_{jx} \\ r_y q_{jy} \end{pmatrix} + \begin{pmatrix} c_x \\ c_y \end{pmatrix}$$

---

### 3. Mathematical Invariants

1. **Non-Negativity of Center Discriminant (Radii Scaling Invariant):**
   $$\frac{r_x^2 r_y^2 - r_x^2 y_1'^2 - r_y^2 x_1'^2}{r_x^2 y_1'^2 + r_y^2 x_1'^2} = \frac{1}{\frac{x_1'^2}{r_x^2} + \frac{y_1'^2}{r_y^2}} - 1 = \frac{1}{\Lambda} - 1$$
   When $\Lambda > 1$, scaling $r_x \mapsto \sqrt{\Lambda}r_x$ and $r_y \mapsto \sqrt{\Lambda}r_y$ maps $\Lambda_{\text{new}} \mapsto \frac{\Lambda}{\Lambda} = 1$, forcing the discriminant to $0$. When $\Lambda \le 1$ (and $\Lambda > 0$), $\frac{1}{\Lambda} - 1 \ge 0$. Thus, over $\mathbb{R}$, the square root argument is strictly non-negative.

2. **$C^0$ Continuity and Endpoint Preservation Invariant:**
   For $i = 0$, $\alpha_1 = \theta_1$. Substituting $Q_0 = (\cos\theta_1, \sin\theta_1) = \mathbf{v}$ into $T(Q_0)$:
   $$T(Q_0) = R(\varphi) \begin{pmatrix} x_1' - c_x' \\ y_1' - c_y' \end{pmatrix} + \begin{pmatrix} c_x \\ c_y \end{pmatrix} = \begin{pmatrix} \frac{x_1 - x_2}{2} \\ \frac{y_1 - y_2}{2} \end{pmatrix} - R(\varphi)\begin{pmatrix} c_x' \\ c_y' \end{pmatrix} + R(\varphi)\begin{pmatrix} c_x' \\ c_y' \end{pmatrix} + \begin{pmatrix} \frac{x_1 + x_2}{2} \\ \frac{y_1 + y_2}{2} \end{pmatrix} = \begin{pmatrix} x_1 \\ y_1 \end{pmatrix} = P_1$$
   By an identical algebraic reduction at $i = N - 1$ where $\alpha_2 = \theta_1 + \Delta\theta$, $T(Q_3) = P_2$. Furthermore, for any adjacent segments $i$ and $i+1$, $Q_{3}^{(i)} = (\cos(\theta_1 + (i+1)\delta\theta), \sin(\theta_1 + (i+1)\delta\theta)) = Q_{0}^{(i+1)}$, guaranteeing $C^0$ (and $G^1$) continuity across segment boundaries. *(Note: In Blink's floating-point implementation, the final endpoint of the last segment is explicitly overwritten with the exact target `p2` to eliminate accumulated rounding drift).*

3. **Determinism Invariant:**
   The decomposition pipeline is a pure mathematical function of the 7-tuple $(P_1, P_2, r_x, r_y, \varphi, f_A, f_S)$ with no dependency on external state or non-deterministic branches.

---

### 4. Formalization in Rocq / Coq (`BlinkSVGArcToBezierSemantics.v`)

Below is a complete, self-contained Rocq (Coq) formalization over the standard real numbers (`Reals`), proving the core invariants.

```coq
(** * BlinkSVGArcToBezierSemantics.v
    Formal verification of Chromium Blink's SVG 2 §9.5 Elliptical Arc
    to Cubic Bézier decomposition pipeline and its mathematical invariants. *)

From Coq Require Import Reals Lra Bool List Arith.
Import ListNotations.
Open Scope R_scope.

(** ** 1. Core Data Structures *)

Record PointF : Type := mkPointF {
  px : R;
  py : R
}.

Record CubicBezier : Type := mkCubic {
  c_p0 : PointF;
  c_p1 : PointF;
  c_p2 : PointF;
  c_p3 : PointF
}.

Record ArcEndpointParam : Type := mkArcEndpoint {
  ae_p1 : PointF;
  