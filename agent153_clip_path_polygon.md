# Audit Report: Chromium Blink Clip Path Polygon Geometry vs. CSS Masking Module Level 1 (§5 & §6)

**Agent ID:** 153  
**Target Component:** `third_party/blink/renderer/core/paint/clip_path_clipper.cc`, `third_party/blink/renderer/core/style/basic_shapes.cc`, `third_party/blink/renderer/platform/graphics/path.cc`  
**Specification:** CSS Masking Module Level 1 (§5 Clipping Paths, §6 The `clip-path` property) & CSS Shapes Module Level 1 (Basic Shapes: `polygon()`)

---

## 1. Representation of Polygonal Clip Paths in `ClipPathClipper` and `Path`

In Chromium Blink, the `clip-path` CSS property with a `<basic-shape>` of type `polygon()` is processed during the PrePaint and Paint lifecycle phases to restrict the painted region of a `LayoutObject`.

### 1.1 Style and BasicShape Representation
* **`BasicShapePolygon`** (`core/style/basic_shapes.h`): Stores the raw CSS polygon definition. It holds a `WindRule` (`RULE_NONZERO` or `RULE_EVENODD`, corresponding to CSS `<fill-rule>`) and a `Vector<Length> values_` where even indices $2i$ represent $x_i$ coordinates and odd indices $2i+1$ represent $y_i$ coordinates.
* **`ShapeClipPathOperation`** (`core/style/shape_clip_path_operation.h`): Wraps the `scoped_refptr<const BasicShape>` and associates it with a `GeometryBox` (per CSS Masking 1 §6.1, defining the reference box).

### 1.2 Path Generation in `ClipPathClipper`
In `core/paint/clip_path_clipper.cc`:
1. **Reference Box Resolution:** `ClipPathClipper::LocalReferenceBox` computes the `gfx::RectF` reference box for the target `LayoutObject` based on the specified `GeometryBox` (e.g., `border-box`, `padding-box`, `content-box`).
2. **Path Construction:** `ClipPathClipper::PathBasedClipInternal` (and `ShapeClipPathOperation::GetPath`) invokes `BasicShapePolygon::GetPath(Path& path, const gfx::RectF& bounding_box, float zoom)`.
3. **Coordinate Resolution and SkPath Backing:**
   Inside `BasicShapePolygon::GetPath`:
   * The `WindRule` is applied to the `blink::Path` (which wraps an `SkPathBuilder` / `SkPath`).
   * For each vertex $i \in \{0, \dots, N-1\}$, concrete floating-point coordinates $(X_i, Y_i)$ are resolved against the `bounding_box` dimensions and offset:
     $$X_i = \text{FloatValueForLength}(x_i, \text{bounding\_box.width}()) + \text{bounding\_box.x}()$$
     $$Y_i = \text{FloatValueForLength}(y_i, \text{bounding\_box.height}()) + \text{bounding\_box.y}()$$
   * For $i = 0$, `path.MoveTo(gfx::PointF(X_0, Y_0))` is called.
   * For $i > 0$, `path.AddLineTo(gfx::PointF(X_i, Y_i))` is called.
   * Finally, `path.CloseSubpath()` implicitly connects $(X_{N-1}, Y_{N-1})$ back to $(X_0, Y_0)$, establishing a closed polygonal contour per CSS Shapes 1.

---

## 2. Bounding Box Computation

In `ClipPathClipper::LocalClipPathBoundingBox`, Blink queries `Path::BoundingRect()` (backed by `SkPath::getBounds()` / `SkPath::computeTightBounds()`).

For a polygonal `Path` consisting solely of linear segments (`MoveTo`, `LineTo`, `CloseSubpath`) over vertices $V = \{(X_0, Y_0), (X_1, Y_1), \dots, (X_{N-1}, Y_{N-1})\}$:
* If $V = \emptyset$, the bounding box is the empty rectangle $(0, 0, 0, 0)$.
* If $V \neq \emptyset$, the axis-aligned bounding box (AABB) is defined by the extrema of the resolved vertex coordinates:
  $$\text{min\_x} = \min_{0 \le i < N} X_i, \quad \text{max\_x} = \max_{0 \le i < N} X_i$$
  $$\text{min\_y} = \min_{0 \le i < N} Y_i, \quad \text{max\_y} = \max_{0 \le i < N} Y_i$$

In `gfx::RectF` representation, this corresponds to:
* `origin()` = $(\text{min\_x}, \text{min\_y})$
* `width()` = $\text{max\_x} - \text{min\_x}$
* `height()` = $\text{max\_y} - \text{min\_y}$

Because every point on an edge of a polygon is a convex combination of two vertices $(1-t)V_i + tV_j$ for $t \in [0, 1]$, the vertex extrema strictly bound the entire continuous geometry of the polygon.

---

## 3. Geometric Invariants

### Invariant 1: Vertex Containment in Bounding Rect
For any non-empty polygon $P$ with vertex list $V$, every vertex $v = (v_x, v_y) \in V$ satisfies:
$$\text{min\_x} \le v_x \le \text{max\_x} \quad \land \quad \text{min\_y} \le v_y \le \text{max\_y}$$

### Invariant 2: Edge and Interior Convex Hull Bound
By convexity of the axis-aligned bounding box $B = [\text{min\_x}, \text{max\_x}] \times [\text{min\_y}, \text{max\_y}]$, any point $p = (p_x, p_y)$ lying on an edge of $P$ or inside the interior of $P$ (under either `nonzero` or `evenodd` winding rules) is a convex combination of vertices in $V$, or bounded by horizontal/vertical ray-casting against edges contained in $B$.

### Invariant 3: Exterior Clip-Out (Containment Necessary Condition)
Per CSS Masking 1 §5, any area outside the clipping path is clipped out (not painted). A point $p$ is inside the polygon $P$ only if its winding number $W(p, P) \neq 0$ (for `nonzero`) or $W(p, P) \pmod 2 \neq 0$ (for `evenodd`).  
If $p \notin B$ (i.e., $p_x < \text{min\_x} \lor p_x > \text{max\_x} \lor p_y < \text{min\_y} \lor p_y > \text{max\_y}$), a ray cast from $p$ away from $B$ intersects $0$ edges of $P$. Thus, $p$ cannot be inside $P$, establishing the **Containment Necessary Condition**:
$$\text{InsidePolygon}(p, P) \implies \text{InsideBoundingBox}(p, B(P))$$
Contrapositively (Fast-Reject Clipping):
$$\neg \text{InsideBoundingBox}(p, B(P)) \implies \neg \text{InsidePolygon}(p, P) \text{ (Clipped Out)}$$

---

## 4. Formal Verification: `BlinkClipPathPolygonSemantics.v`

The following self-contained Rocq (Coq) script formalizes the polygonal representation, bounding box computation, vertex containment invariant, edge containment, and the necessary condition for polygon containment (clip-out outside bounding box).

```coq
(** * BlinkClipPathPolygonSemantics.v
    Formal Audit of Chromium Blink ClipPathClipper Polygon Geometry
    vs. CSS Masking Module Level 1 (§5 & §6). *)

From Coq Require Import Reals Lra List Bool.
Import ListNotations.
Open Scope R_scope.

(** ** 1. Geometric Primitives and Polygon Representation *)

Record PointF : Type := mkPointF {
  px : R;
  py : R
}.

Record RectBounds : Type := mkRectBounds {
  min_x : R;
  max_x : R;
  min_y : R;
  max_y : R
}.

Inductive WindRule : Type :=
  | RULE_NONZERO
  | RULE_EVENODD.

Record BasicShapePolygon : Type := mkPolygon {
  wind_rule : WindRule;
  vertices : list PointF
}.

(** Point containment within an Axis-Aligned Bounding Box (AABB). *)
Definition in_bounds (p : PointF) (b : RectBounds) : Prop :=
  b.(min_x) <= p.(px) <= b.(max_x) /\
  b.(min_y) <= p.(py) <= b.(max_y).

(** ** 2. Bounding Box Computation (SkPath::computeTightBounds for Polygons) *)

Fixpoint compute_bounds_ vertices (acc : RectBounds) : RectBounds :=
  match vertices with
  | [] => acc
  | v :: vs =>
      let next_acc := mkRectBounds
        (Rmin acc.(min_x) v.(px))
        (Rmax acc.(max_x) v.(px))
        (Rmin acc.(min_y) v.(py))
        (Rmax acc.(max_y) v.(py))
      in compute_bounds_ vs next_acc
  end.

Definition polygon_bounding_box (poly : BasicShapePolygon) : option RectBounds :=
  match poly.(vertices) with
  | [] => None
  | v0 :: vs =>
      Some (compute_bounds_ vs (mkRectBounds v0.(px) v0.(px) v0.(py) v0.(py)))
  end.

(** ** 3. Lemmas for Monotonicity of Bounding Accumulator *)

Lemma Rmin_le_left : forall a b, Rmin a b <= a.
Proof. intros a b; unfold Rmin; destruct (Rle_dec a b); lra. Qed.

Lemma Rmin_le_right : forall a b, Rmin a b <= b.
Proof. intros a b; unfold Rmin; destruct (Rle_dec a b); lra. Qed.

Lemma Rmax_ge_left : forall a b, a <= Rmax a b.
Proof. intros a b; unfold Rmax; destruct (Rle_dec a b); lra. Qed.

Lemma Rmax_ge_right : forall a b, b <= Rmax a b.
Proof. intros a b; unfold Rmax; destruct (Rle_dec a b); lra. Qed.

Lemma compute_bounds_monotonic : forall vs acc,
  (compute_bounds_ vs acc).(min_x) <= acc.(min_x) /\
  acc.(max_x) <= (compute_bounds_ vs acc).(max_x) /\
  (compute_bounds_ vs acc).(min_y) <= acc.(min_y) /\
  acc.(max_y) <= (compute_bounds_ vs acc).(max_y).
Proof.
  induction vs as [| v vs IH]; intros acc; simpl.
  - lra.
  - destruct (IH (mkRectBounds
                    (Rmin acc.(min_x) v.(px))
                    (Rmax acc.(max_x) v.(px))
                    (Rmin acc.(min_y) v.(py))
                    (Rmax acc.(max_y) v.(py)))) as [Hminx [Hmaxx [Hminy Hmaxy]]].
    pose proof (Rmin_le_left acc.(min_x) v.(px)).
    pose proof (Rmax_ge_left acc.(max_x) v.(px)).
    pose proof (Rmin_le_left acc.(min_y) v.(py)).
    pose proof (Rmax_ge_left acc.(max_y) v.(py)).
    simpl in *. lra.
Qed.

Lemma compute_bounds_contains_acc : forall vs acc p,
  in_bounds p acc ->
  in_bounds p (compute_bounds_ vs acc).
Proof.
  intros vs acc p [Hx Hy].
  destruct (compute_bounds_monotonic vs acc) as [Hminx [Hmaxx [Hminy Hmaxy]]].
  unfold in_bounds; lra.
Qed.

Lemma compute_bounds_contains_vertices : forall vs acc v,
  In v vs ->
  in_bounds v (compute_bounds_ vs acc).
Proof.
  induction vs as [| v0 vs IH]; intros acc v HIn; simpl in *.
  - contradiction.
  - destruct HIn as [Heq | HIn].
    + subst v.
      apply compute_bounds_contains_acc.
      unfold in_bounds; simpl.
      pose proof (Rmin_le_right acc.(min_x) v0.(px)).
      pose proof (Rmax_ge_right acc.(max_x) v0.(px)).
      pose proof (Rmin_le_right acc.(min_y) v0.(py)).
      pose proof (Rmax_ge_right acc.(max_y) v0.(py)).
      lra.
    + apply IH; assumption.
Qed.

(** ** 4. Theorem 1: Polygon Bounding Rect Contains All Vertices *)

Theorem polygon_bounds_contains_all_vertices :
  forall (poly : BasicShapePolygon) (b : RectBounds) (v : PointF),
    polygon_bounding_box poly = Some b ->
    In v poly.(vertices) ->
    in_bounds v b.
Proof.
  intros poly b v Hbox HIn.
  unfold polygon_bounding_box in Hbox.
  destruct poly.(vertices) as [| v0 vs] eqn:Hverts.
  - discriminate Hbox.
  - injection Hbox as Hbox; subst b.
    simpl in HIn. destruct HIn as [Heq | HIn].
    + subst v.
      apply compute_bounds_contains_acc.
      unfold in_bounds; simpl; lra.
    + apply compute_bounds_contains_vertices; assumption.
Qed.

(** ** 5. Polygon Interior Semantics & Ray-Casting / Convexity Bound *)

(** A horizontal ray from point [p] to (-infinity, p.py) can only intersect
    a polygon segment (u, w) if p.py is between u.py and w.py, and p.px is at least
    min(u.px, w.px). Similarly, a ray to (+infinity, p.py) requires p.px <= max(u.px, w.px).
    More generally, any point inside a closed polygon under CSS Masking 1 §5 & §6
    (either nonzero or evenodd winding rule) must lie within the horizontal and vertical
    spans of the polygon's edges, which are convex combinations of the vertices. *)

Definition on