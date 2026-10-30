# Formal Verification Report: CSS `shape-margin` Dilation Expansion in Chromium Blink

**Agent:** Formal Verification Agent 700 (W3C/WHATWG Layout Rules: Grid, Tables, Shapes)  
**Topic:** CSS `shape-margin` dilation expansion around shape geometry  
**Chromium Source:** `third_party/blink/renderer/core/layout/shapes/shape.cc`  
**Specification:** CSS Shapes Module Level 1, §3.2 (`shape-margin` property) and §6.2 (The `shape-margin` Property)  
**Formal Theory Target:** `BlinkShapeMarginExpansionGeometrySemantics.v`  
**Mathematical Property:** $\text{expanded\_radius}(r, \text{margin}) = r + \max(0, \text{margin}) \implies \text{expanded\_radius}(r, \text{margin}) \ge r$

---

## 1. Normative W3C CSS Shapes Specification Requirements

The CSS Shapes Module Level 1 specification defines geometric shapes that inline content wraps around (`shape-outside`). To separate the inline content from the boundary of the extracted or specified shape, the specification introduces the `shape-margin` property.

### 1.1 Normative Definitions (CSS Shapes 1 §3.2 & §6.2)
* **Property Definition (§6.2):** The `shape-margin` property adds a margin to a `shape-outside`. It accepts `<length-percentage [0,∞)>` values. Negative values are invalid at parse-time and clamped to $0$ at computation-time.
* **Geometric Expansion Semantics (§3.2 & §6.2):** It defines a new shape that is the smallest contour (in the shrink-wrap sense) that includes all the points that are less than or equal to the `shape-margin` distance outward in the perpendicular direction from a point on the underlying shape.
* **Minkowski Sum Formulation:** Mathematically, given an underlying closed 2D shape $S \subset \mathbb{R}^2$ and a computed margin $m = \max(0, \text{margin}) \in \mathbb{R}_{\ge 0}$, the expanded shape $S_m$ is the Minkowski sum of $S$ and a closed disk $D_m = \{ p \in \mathbb{R}^2 \mid \|p\|_2 \le m \}$:
  $$S_m = S \oplus D_m = \{ s + d \mid s \in S, d \in D_m \}$$
* **Curvature and Corner Dilation:** At sharp vertices (e.g., polygon corners) or along circular/elliptical arcs of radius $r$, the outward perpendicular expansion dilates the local radius of curvature by $m$:
  $$r_{\text{expanded}} = r + \max(0, m)$$
* **Monotonicity Invariant:** Adding a `shape-margin` never shrinks the exclusion area of the shape. For any horizontal scanline $Y$ or vertical interval $[y_1, y_2]$, the excluded inline interval $[x_{\text{left}}, x_{\text{right}}]$ of the dilated shape must be a superset of the underlying shape's excluded interval.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, CSS Shapes geometry and margin expansion are implemented in `third_party/blink/renderer/core/layout/shapes/`.

### 2.1 Core Architecture in `shape.cc` and Subclasses
1. **`Shape::CreateShape` (`shape.cc`):**
   When constructing a `Shape` instance (specifically `BoxShape`, `InsetShape`, `CircleShape`, `EllipseShape`, `PolygonShape`, or `RasterShape`), `shape_margin` is resolved from the `ComputedStyle` and converted to `float` layout coordinates via `FloatValueForLength`.
   ```cpp
   float margin = FloatValueForLength(style.ShapeMargin(), box_width);
   margin = std::max(0.0f, margin); // Enforces non-negativity invariant
   ```
   The sanitized margin is stored in `Shape::margin_` and accessible via `Shape::ShapeMargin()`.

2. **Radial Dilation (`CircleShape` & `EllipseShape`):**
   * In `CircleShape::GetExcludedIntervals(LayoutUnit logical_top, LayoutUnit logical_height)` and `EllipseShape::GetExcludedIntervals`, the effective radii Used for interval projection are computed via `ShapeMargin()` dilation:
     ```cpp
     float margin_radius = radius_ + ShapeMargin();
     ```
     For `EllipseShape`, both axes are dilated independently:
     ```cpp
     float margin_radius_x = radii_.Width() + ShapeMargin();
     float margin_radius_y = radii_.Height() + ShapeMargin();
     ```
   * The bounding box (`ShapeMarginBounds()`) expands outward by `ShapeMargin()` in all four cardinal directions:
     $$[x - r_x - m, \; x + r_x + m] \times [y - r_y - m, \; y + r_y + m]$$

3. **Box & Inset Corner Dilation (`BoxShape` & `InsetShape`):**
   * A rounded rectangle (`FloatRoundedRect`) with corner radii $(r_{tl}, r_{tr}, r_{bl}, r_{br})$ is dilated by `ShapeMargin()` using `FloatRoundedRect::OutsetForShapeMargin(float outset)`.
   * Each corner ellipse radius $(r_x, r_y)$ is expanded precisely to $(r_x + m, r_y + m)$, maintaining $G^1$ geometric continuity between the straight edges (shifted outward by $m$) and the corner arcs.

4. **Polygon Offset and Vertex Arc Dilation (`PolygonShape`):**
   * Each polygon edge is displaced outward along its normal by `ShapeMargin()` (`OffsetPolygonEdge`).
   * Each polygon vertex $V_i$ is surrounded by a circular cap of radius $r = 0 + \text{ShapeMargin()} = \text{ShapeMargin()}$ to capture the exact Euclidean distance locus required by CSS Shapes §6.2.

5. **Raster Shape Dilation (`RasterShape`):**
   * `RasterShapeIntervals::ComputeShapeMarginIntervals(int shape_margin)` constructs a discrete circular kernel (using integer Midpoint/Pythagorean circle lookup) of radius $r_{\text{margin}} = \lceil\text{ShapeMargin()}\rceil$ and performs 2D morphological dilation over the run-length encoded (RLE) `LineSegment` intervals.

### 2.2 Critical Layout Invariants in Blink
* **Invariant 1 (Non-negative Margin Clamping):** `Shape::ShapeMargin() >= 0` holds across all shape instances regardless of CSS calc() evaluation or subpixel rounding anomalies.
* **Invariant 2 (Radial Monotonicity):** For any radial parameter $r \ge 0$ (circle radius, ellipse semi-axis, rounded rect corner radius, or polygon vertex cap radius $r=0$), the dilated radius $r' = r + \max(0, \text{margin})$ satisfies $r' \ge r$ and $r' \ge 0$.
* **Invariant 3 (Bounding Box Inclusion):** `ShapeMarginLogicalBoundingBox()` always encloses `LogicalBoundingBox()`.
* **Invariant 4 (Scanline Interval Monotonicity):** If a horizontal line segment $[x_1, x_2]$ is excluded by the base shape at scanline $y$, the dilated interval $[x_1', x_2']$ satisfies $x_1' \le x_1$ and $x_2' \ge x_2$.

---

## 3. Formal Specification Definitions in Rocq/Coq

To formally verify the discrete and fixed-point (`LayoutUnit` / integer subpixel) arithmetic properties of Blink's `shape.cc` dilation logic without floating-point NaN/overflow ambiguity, we model coordinates, radii, and margins over $\mathbb{Z}$ (representing subpixel `LayoutUnit` ticks or pixel units).

We define:
* `Z_max0`: The clamping operator $\max(0, m)$ used in `Shape::CreateShape`.
* `expanded_radius`: The core dilation equation $r + \max(0, m)$.
* `Shape1DInterval`: A 1D scanline projection $[x_{\text{left}}, x_{\text{right}}]$.
* `CircleGeometry` & `EllipseGeometry`: 2D geometric representations matching Blink's `CircleShape` and `EllipseShape`.
* `BoxCornerGeometry`: 2D corner radii matching `FloatRoundedRect::OutsetForShapeMargin`.

---

## 4. Formal Theory and Complete Proofs (`BlinkShapeMarginExpansionGeometrySemantics.v`)

Below is the complete, self-contained, admitted-free Rocq/Coq development verifying the `shape-margin` expansion semantics.

```coq
(** * BlinkShapeMarginExpansionGeometrySemantics.v
    Formal Verification of W3C CSS Shapes 1 §3.2 & §6.2 shape-margin Dilation
    Target: third_party/blink/renderer/core/layout/shapes/shape.cc
    Agent: Formal Verification Agent 700
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ========================================================================= *)
(** ** 1. Core Definitions: Margin Clamping and Radius Expansion              *)
(** ========================================================================= *)

(** Sanitized shape-margin clamp: CSS Shapes 1 §6.2 specifies that negative
    shape-margin values are invalid; Blink enforces std::max(0, margin). *)
Definition clamp_margin (margin : Z) : Z :=
  Z.max 0 margin.

(** Core radius dilation equation from CircleShape, EllipseShape, BoxShape,
    and PolygonShape vertex caps in shape.cc:
    expanded_radius(r, margin) = r + max(0, margin). *)
Definition expanded_radius (r margin : Z) : Z :=
  r + clamp_margin margin.

(** ========================================================================= *)
(** ** 2. Fundamental Algebraic & Monotonicity Theorems                       *)
(** ========================================================================= *)

(** Theorem 1: Clamped margin is strictly non-negative. *)
Theorem clamp_margin_nonneg : forall (margin : Z),
  0 <= clamp_margin margin.
Proof.
  intros margin.
  unfold clamp_margin.
  lia.
Qed.

(** Theorem 2: Primary Specification Target:
    expanded_radius(r, margin) = r + max(0, margin) >= r. *)
Theorem expanded_radius_ge_base : forall (r margin : Z),
  r <= expanded_radius r margin.
Proof.
  intros r margin.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** Theorem 3: Non-negativity preservation for valid base radii (r >= 0). *)
Theorem expanded_radius_nonneg : forall (r margin : Z),
  0 <= r ->
  0 <= expanded_radius r margin.
Proof.
  intros r margin Hr.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** Theorem 4: Identity under non-positive margin (margin <= 0). *)
Theorem expanded_radius_nonpos_margin_id : forall (r margin : Z),
  margin <= 0 ->
  expanded_radius r margin = r.
Proof.
  intros r margin Hmargin.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** Theorem 5: Exact linear dilation under non-negative margin (margin >= 0). *)
Theorem expanded_radius_nonneg_margin_linear : forall (r margin : Z),
  0 <= margin ->
  expanded_radius r margin = r + margin.
Proof.
  intros r margin Hmargin.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** Theorem 6: Monotonicity with respect to base radius r. *)
Theorem expanded_radius_mono_r : forall (r1 r2 margin : Z),
  r1 <= r2 ->
  expanded_radius r1 margin <= expanded_radius r2 margin.
Proof.
  intros r1 r2 margin Hr.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** Theorem 7: Monotonicity with respect to shape-margin. *)
Theorem expanded_radius_mono_margin : forall (r m1 m2 : Z),
  m1 <= m2 ->
  expanded_radius r m1 <= expanded_radius r m2.
Proof.
  intros r m1 m2 Hm.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** Theorem 8: Associativity / Composition of successive margin dilations. *)
Theorem expanded_radius_compose : forall (r m1 m2 : Z),
  expanded_radius (expanded_radius r m1) m2 =
  r + clamp_margin m1 + clamp_margin m2.
Proof.
  intros r m1 m2.
  unfold expanded_radius, clamp_margin.
  lia.
Qed.

(** ========================================================================= *)
(** ** 3. 1D Scanline Interval Dilation Semantics (LineSegment in shape.cc)   *)
(** ========================================================================= *)

(** Represents Blink's LineSegment [left, right] returned by
    Shape::GetExcludedIntervals. *)
Record LineSegment : Type := mkSegment {
  seg_left  : Z;
  seg_right : Z
}.

(** A LineSegment is well-formed if left <= right. *)
Definition wf_segment (s : LineSegment) : Prop :=
  seg_left s <= seg_right s.

(** Width of an excluded scanline segment. *)
Definition segment_width (s : LineSegment) : Z :=
  seg_right s - seg_left s.

(** Segment inclusion: s1 is contained within s2 (s1 <= s2 in exclusion ordering). *)
Definition segment_subset (s1 s2 : LineSegment) : Prop :=
  seg_left s2 <= seg_left s1 /\ seg_right s1 <= seg_right s2.

(** Radial interval centered at c with radius r: [c - r, c + r]. *)
Definition radial_segment (center r : Z) : LineSegment :=
  mkSegment (center - r) (center + r).

(** Dilated radial interval centered at c with base radius r and margin m. *)
Definition dilated_radial_segment (center r margin : Z) : LineSegment :=
  radial_segment center (expanded_radius r margin).

(** Theorem 9: Well-formedness of dilated radial segments for r >= 0. *)
Theorem dilated_radial_segment_wf : forall (center r margin : Z),
  0 <= r ->
  wf_segment (dilated_radial_segment center r margin).
Proof.
  intros center r margin Hr.
  unfold dilated_radial_segment, radial_segment, wf_segment, expanded_radius, clamp_margin.
  simpl.
  lia.
Qed.

(** Theorem 10: Scanline Interval Inclusion Invariant.
    The dilated radial segment always encloses the base radial segment. *)
Theorem dilated_radial_segment_encloses_base : forall (center r margin : Z),
  segment_subset (radial_segment center r) (dilated_radial_segment center r margin).
Proof.
  intros center r margin.
  unfold dilated