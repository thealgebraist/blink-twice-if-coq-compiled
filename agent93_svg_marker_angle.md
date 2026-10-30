### 1. Core Data Structures in Blink SVG Marker Layout

In Chromium’s Blink rendering engine (`third_party/blink/renderer/core/layout/svg/`), marker orientation and positioning are decoupled into path geometry extraction and resource transformation calculation.

#### `FloatPoint` & `FloatVector2D` (now `gfx::PointF` and `gfx::Vector2dF`)
* **Representation**: Standard IEEE 754 single-precision floating-point coordinates `(x, y)`.
* **Operations**:
  * Subtraction of two `PointF` instances yields a `Vector2dF` representing the unnormalized directional chord or tangent: $\vec{v} = P_2 - P_1 = (\Delta x, \Delta y)$.
  * Angle extraction via `atan2f(v.y(), v.x())`, returning radians in $[-\pi, \pi]$, which Blink converts to degrees via `rad2deg`.

#### `MarkerPosition` (`svg_marker_data.h`)
Represents a resolved marker instance on a path vertex:
```cpp
struct MarkerPosition {
  enum SVGMarkerType { kStartMarker, kMidMarker, kEndMarker };
  
  LayoutSVGResourceMarker* marker;
  gfx::PointF origin;
  float angle; // Stored in degrees
  SVGMarkerType type;
};
```

#### `SVGMarkerData` & `SVGMarkerDataBuilder` (`svg_marker_data.h/.cc`)
A state machine invoked via `Path::Apply()` that iterates over path segments (`kPathElementMoveToPoint`, `kPathElementAddLineToPoint`, `kPathElementAddQuadCurveToPoint`, `kPathElementAddCurveToPoint`, `kPathElementCloseSubpath`) to compute vertex tangents and populate a `Vector<MarkerPosition>`.
* **Key internal state**:
  * `origin_`: Current vertex coordinate $P_i$.
  * `subpath_start_`: Coordinate of the last `MoveTo` $P_{\text{start}}$, used for `CloseSubpath` vector calculation and closed-loop start/end angle matching.
  * `in_slope_`: Incoming tangent vector $\vec{v}_{\text{in}}$ at $P_i$.
  * `out_slope_`: Outgoing tangent vector $\vec{v}_{\text{out}}$ at $P_i$.
  * `positions_`: Output buffer of `MarkerPosition` structs.

#### `LayoutSVGResourceMarker` (`layout_svg_resource_marker.h/.cc`)
Manages the `<marker>` layout element and computes the local-to-parent transformation matrix (`AffineTransform`).
* **Key attributes**:
  * `SVGMarkerOrientType`: `kSVGMarkerOrientAngle`, `kSVGMarkerOrientAuto`, `kSVGMarkerOrientAutoStartReverse`.
  * `Angle()`: Explicit float angle when `orient` is a static degree/radian value.
* **`MarkerTransformation(const MarkerPosition&, float stroke_width)`**: Combines translation to `origin`, rotation by the resolved angle (accounting for `orient` type), scaling by `stroke_width` (if `markerUnits="strokeWidth"`), and viewBox/refX/refY alignment.

---

### 2. Auto Angle Calculation (`orient="auto"`)

According to SVG 2 §13.6.2 (and implemented in `SVGMarkerDataBuilder`), the orientation angle $\theta$ at a given vertex $P_i$ is derived from the incoming tangent vector $\vec{v}_{\text{in}}$ and outgoing tangent vector $\vec{v}_{\text{out}}$.

#### Tangent Extraction per Segment
For a segment defined by control points $(C_0, C_1, \dots, C_n)$:
* **Line ($C_0, C_1$)**: $\vec{v}_{\text{in}} = \vec{v}_{\text{out}} = C_1 - C_0$.
* **Quadratic Bézier ($C_0, C_1, C_2$)**: $\vec{v}_{\text{out}} = C_1 - C_0$ (at start), $\vec{v}_{\text{in}} = C_2 - C_1$ (at end). If $C_1 = C_0$ (degenerate control point), $\vec{v}_{\text{out}} = C_2 - C_0$.
* **Cubic Bézier ($C_0, C_1, C_2, C_3$)**: $\vec{v}_{\text{out}}$ is the first non-zero vector in $(C_1 - C_0, C_2 - C_0, C_3 - C_0)$. $\vec{v}_{\text{in}}$ is the first non-zero vector in $(C_3 - C_2, C_3 - C_1, C_3 - C_0)$.

Let $\operatorname{ang}(\vec{v}) = \operatorname{atan2}(v_y, v_x) \cdot \frac{180}{\pi} \in (-180^\circ, 180^\circ]$. Notice that $\operatorname{ang}(\vec{0}) = 0^\circ$.

#### Vertex Type Resolution (`CurrentAngle` in Blink)
1. **Start Marker (`kStartMarker`)**:
   * **Open subpath**: $\vec{v}_{\text{in}} = \vec{0}$. Angle is purely determined by the outgoing tangent:
     $$\theta_{\text{start}} = \operatorname{ang}(\vec{v}_{\text{out}})$$
   * **Closed subpath** (ends with `Z` or `z`): $\vec{v}_{\text{in}}$ is set to the final segment's incoming tangent into $P_{\text{start}}$. It uses the bisector formula (same as Mid Marker).

2. **End Marker (`kEndMarker`)**:
   * **Open subpath**: $\vec{v}_{\text{out}} = \vec{0}$. Angle is purely determined by the incoming tangent:
     $$\theta_{\text{end}} = \operatorname{ang}(\vec{v}_{\text{in}})$$
   * **Closed subpath**: $\vec{v}_{\text{out}}$ is set to the initial segment's outgoing tangent from $P_{\text{start}}$. Uses the bisector formula.

3. **Mid Marker (`kMidMarker`) — Bisector Calculation**:
   Let $\theta_{\text{in}} = \operatorname{ang}(\vec{v}_{\text{in}})$ and $\theta_{\text{out}} = \operatorname{ang}(\vec{v}_{\text{out}})$.
   Because `atan2` has a branch cut at $\pm 180^\circ$, naive averaging fails when the vectors straddle the negative X-axis (e.g., $\theta_{\text{in}} = 170^\circ, \theta_{\text{out}} = -170^\circ \implies \text{naive average } 0^\circ$, whereas the true bisector in the direction of path travel is $\pm 180^\circ$).
   
   Blink resolves the branch cut discontinuity in `SVGMarkerDataBuilder::BisectingAngle`:
   ```cpp
   float BisectingAngle(float in_angle, float out_angle) {
     if (std::abs(in_angle - out_angle) > 180)
       in_angle += 360;
     return (in_angle + out_angle) / 2;
   }
   ```
   Mathematically:
   $$\theta_{\text{mid}} = \begin{cases} \frac{\theta_{\text{in}} + \theta_{\text{out}} + 360^\circ}{2} & \text{if } |\theta_{\text{in}} - \theta_{\text{out}}| > 180^\circ \\ \frac{\theta_{\text{in}} + \theta_{\text{out}}}{2} & \text{otherwise} \end{cases}$$

---

### 3. `auto-start-reverse` Angle Reflection

Introduced in SVG 2 §13.6.2 to allow a single arrowhead marker definition to be used for both `marker-start` and `marker-end` (pointing outward at both ends of a path).

In `LayoutSVGResourceMarker::MarkerTransformation`:
```cpp
float angle = position.angle;
if (OrientType() == kSVGMarkerOrientAutoStartReverse &&
    position.type == MarkerPosition::kStartMarker) {
  angle += 180;
}
```
#### Formal Semantics
Given a resolved `MarkerPosition` with base auto-angle $\theta_{\text{auto}}$:
$$\theta_{\text{final}}(\text{orient}, \text{type}, \theta_{\text{explicit}}, \theta_{\text{auto}}) = \begin{cases} 
\theta_{\text{explicit}} & \text{if } \text{orient} = \text{Angle} \\
\theta_{\text{auto}} & \text{if } \text{orient} = \text{Auto} \\
\theta_{\text{auto}} + 180^\circ \pmod{360^\circ} & \text{if } \text{orient} = \text{AutoStartReverse} \land \text{type} = \text{Start} \\
\theta_{\text{auto}} & \text{if } \text{orient} = \text{AutoStartReverse} \land \text{type} \neq \text{Start}
\end{cases}$$

In radians, the reflection is $\theta \mapsto (\theta + \pi) \bmod 2\pi$, which corresponds to the orthogonal matrix transformation $R(\theta + \pi) = -R(\theta)$, inverting both basis axes of the marker coordinate system.

---

### 4. Mathematical Invariants

1. **Angle Normalization and Equivalence ($\mathbb{R} / 2\pi\mathbb{Z}$)**:
   Any marker orientation angle $\theta \in \mathbb{R}$ is canonically projected onto $[0, 2\pi)$ (or $[0^\circ, 360^\circ)$) via:
   $$\operatorname{norm}(\theta) = \theta - 2\pi \left\lfloor \frac{\theta}{2\pi} \right\rfloor$$
   **Invariant**: $\forall \theta \in \mathbb{R}, k \in \mathbb{Z}, \quad R(\operatorname{norm}(\theta)) = R(\theta + 2\pi k)$, where $R(\alpha)$ is the 2D rotation matrix. Note that in Blink’s `BisectingAngle`, adding $360^\circ$ unconditionally when $|\theta_{\text{in}} - \theta_{\text{out}}| > 180^\circ$ shifts the result by $+180^\circ$, which is always congruent modulo $360^\circ$ to subtracting $360^\circ$ (since $\frac{x + 360}{2} - \frac{x - 360}{2} = 360 \equiv 0 \pmod{360}$).

2. **Bisector Angle Continuity and Collinear Identity**:
   * **Collinear Identity**: If incoming and outgoing segments have identical tangent directions ($\theta_{\text{in}} = \theta_{\text{out}}$), the bisector is strictly $\theta_{\text{in}}$.
   * **Symmetry modulo $2\pi$**: $\operatorname{norm}(\operatorname{bisect}(\theta_1, \theta_2)) = \operatorname{norm}(\operatorname{bisect}(\theta_2, \theta_1))$.
   * **Continuity**: For $\theta_{\text{in}}, \theta_{\text{out}} \in (-\pi, \pi]$ such that $|\theta_{\text{in}} - \theta_{\text{out}}| \neq \pi$ (the cusp/180-degree reversal singularity), the map $(\vec{v}_{\text{in}}, \vec{v}_{\text{out}}) \mapsto R(\operatorname{bisect}(\theta_{\text{in}}, \theta_{\text{out}}))$ is continuous across the $\pm \pi$ branch cut.

3. **Scale Preservation of Marker Transform**:
   In `LayoutSVGResourceMarker::MarkerTransformation`, the local transform is built via:
   $$M = T(P_{\text{origin}}) \cdot R(\theta_{\text{final}}) \cdot S(s) \cdot T(-P_{\text{ref}})$$
   where $s = \text{strokeWidth}$ (if `markerUnits="strokeWidth"`) or $s = 1$ (if `markerUnits="userSpaceOnUse"`).
   **Invariant**: The orientation step $R(\theta_{\text{final}})$ is an element of $SO(2)$ ($\det(R) = \cos^2\theta + \sin^2\theta = 1$, $R^T R = I$). Therefore, the determinant (area scale factor) of the combined marker transformation matrix $M$ is completely invariant with respect to $\theta_{\text{final}}$ and `SVGMarkerOrientType`:
   $$\det(M_{\text{linear}}) = s^2, \quad \forall \vec{v} \in \mathbb{R}^2, \| R(\theta_{\text{final}}) \cdot S(s) \vec{v} \|_2 = |s| \|\vec{v}\|_2$$

---

### 5. Rocq / Coq Formalization (`BlinkSVGMarkerAngleSemantics.v`)

The following file is a complete, self-contained formalization in Coq (Rocq) using the standard Reals library (`Coq.Reals.Reals`). It formalizes the Blink data types, the exact branch-cut-aware bisector algorithm, `auto-start-reverse` reflection, and proves key invariants including scale preservation, collinearity, and branch-cut sign invariance.

```coq
(** * BlinkSVGMarkerAngleSemantics.v
    Formal verification of Chromium Blink SVG Marker Orientation
    against SVG 2 Specification §13.6.2. *)

From Coq Require Import Reals Lra.
Local Open Scope R_scope.

(** ** 1. Core Data Structures *)

Inductive SVGMarkerType : Type :=
  | StartMarker
  | MidMarker
  | EndMarker.

Inductive SVGMarkerOrientType : Type :=
  | OrientAngle (explicit_deg : R)
  | OrientAuto
  | OrientAutoStartReverse.

Record FloatPoint : Type := mkPoint {
  px : R;
  py : R
}.

Record MarkerPosition : Type := mkMarkerPosition {
  mp_origin : FloatPoint;
  mp_angle  : R; (* Stored in degrees, matching Blink's SVGMarkerData *)
  mp_type   : SVGMarkerType
}.

(** ** 2. Auto Angle & Bisector Calculation *)

(** Blink's SVGMarkerDataBuilder::BisectingAngle:
    if (std::abs(in_angle - out_angle) > 180)
      in_angle += 360;
    return (in_angle + out_angle) / 2; *)
Definition Rabs_gt_180_dec (a b : R) : {Rabs (a - b) > 180} + {Rabs (a - b) <= 180}.
Proof.
  destruct (Rgt_dec (Rabs (a - b)) 180); [left | right]; lra.
Defined.

Definition bisecting_angle (in_angle out_angle : R) : R :=
  if Rabs_gt_180_dec in_angle out_angle then
    (in_angle + 360 + out_angle) / 2
  else
    (in_angle + out_angle) / 2.

(** Vertex angle resolution in SVGMarkerData