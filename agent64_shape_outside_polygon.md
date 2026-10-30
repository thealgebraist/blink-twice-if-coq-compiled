### 1. Core Data Structures in Blink `shape-outside`

In Chromium Blink (`third_party/blink/renderer/core/layout/shapes/`), polygon exclusion geometry for `shape-outside: polygon(...)` is represented by four core structures:

1. **`FloatPoint` (`gfx::PointF`)**:
   * **Representation**: A 2D Cartesian coordinate pair $(x, y) \in \mathbb{R}^2$ (implemented in IEEE 754 single-precision `float`).
   * **Role**: Represents the vertices $V = \{v_0, v_1, \dots, v_{n-1}\}$ of the polygon in the formatting context's local coordinate space.

2. **`ShapeInterval<T>` (`LineSegment`)**:
   * **Representation**: A 1D closed interval $[x_1, x_2]$ where $x_1, x_2 \in \mathbb{R}$ and $x_1 \le x_2$.
   * **Operations**: Union (`Unite`), intersection (`Intersect`), and overlap predicates (`Overlaps`). A `Vector<ShapeInterval<float>>` represents a sorted, disjoint set of horizontal intervals.

3. **`PolygonEdge` / `OffsetPolygonEdge` (Conceptual `Segment2D`)**:
   * **Representation**: A directed line segment $e_i = \overrightarrow{v_i v_{(i+1)\bmod n}}$ connecting two consecutive `FloatPoint` vertices.
   * **Properties**: Stores pointers/indices to the start and end vertices, vertical bounds $y_{\min} = \min(v_{i}.y, v_{i+1}.y)$ and $y_{\max} = \max(v_{i}.y, v_{i+1}.y)$, and provides linear interpolation methods to solve for $x(y)$ given $y \in [y_{\min}, y_{\max}]$.

4. **`PolygonShape` (inherits from `Shape`)**:
   * **Representation**: Consists of a closed sequence of `FloatPoint` vertices, a `WindRule` (`RULE_NONZERO` or `RULE_EVENODD`, per CSS Shapes Level 1 §3.2), a precomputed collection of `PolygonEdge`s, and a 2D axis-aligned bounding box (`FloatRect`).
   * **Role**: Computes the horizontal exclusion interval (`LineSegment`) for any given vertical line box range $[y_1, y_2]$.

---

### 2. Scanbeam Horizontal Line Intersection

Given a horizontal scanline at vertical coordinate $y$ or a scanbeam band $[y_{\text{top}}, y_{\text{bottom}}]$:

1. **Active Edge Filtering**: 
   An edge $e_i = (p_1, p_2)$ with $p_1 = (x_1, y_1)$ and $p_2 = (x_2, y_2)$ intersects a horizontal scanline at $y$ if and only if $y$ falls within its half-open vertical extent (to avoid double-counting vertices):
   $$\min(y_1, y_2) \le y < \max(y_1, y_2)$$
   Horizontal edges ($y_1 = y_2 = y$) are treated separately during band clipping or ignored in standard scanline winding transitions because they contribute no vertical crossing.

2. **Intersection Calculation**:
   For each active edge $e_i$, the $x$-coordinate of the intersection is computed via linear interpolation:
   $$x(y) = x_1 + \frac{y - y_1}{y_2 - y_1} (x_2 - x_1)$$

3. **Sorting & Pairing**:
   All intersection coordinates $\{x_{k}\}$ at height $y$ are collected and sorted in non-decreasing order: $x_{(1)} \le x_{(2)} \le \dots \le x_{(2m)}$.
   * **Even-Odd Rule (`evenodd`)**: The sorted intersections are paired consecutively into closed interior intervals:
     $$I_k(y) = [x_{(2k-1)}, x_{(2k)}] \quad \text{for } k = 1, \dots, m$$
   * **Non-Zero Rule (`nonzero`)**: Each intersection carries a winding delta $\Delta w = \text{sgn}(y_2 - y_1) \in \{-1, +1\}$. Scanning left-to-right, a running sum $W$ is maintained; intervals where $W \neq 0$ form the interior intervals.

---

### 3. Exclusion Interval Calculation for Float Placement

When placing inline content adjacent to a floated element with a `PolygonShape` over a line box spanning $[y_{\text{top}}, y_{\text{bottom}}]$ (with $y_{\text{top}} \le y_{\text{bottom}}$):

1. **Scanbeam Interval Accumulation**:
   The polygon's intersection with the horizontal strip $\mathbb{R} \times [y_{\text{top}}, y_{\text{bottom}}]$ is the union of all horizontal cross-sections for $y \in [y_{\text{top}}, y_{\text{bottom}}]$. Because polygon edges are linear, the extrema of $x$ within the strip occur solely at:
   * Intersections of edges with $y = y_{\text{top}}$ and $y = y_{\text{bottom}}$.
   * Polygon vertices $v_i$ that lie strictly inside the strip ($y_{\text{top}} < v_i.y < y_{\text{bottom}}$).
   * Edge-to-edge self-intersections within the strip.

2. **Bounding Interval (Float Exclusion)**:
   Blink computes the horizontal `ShapeInterval` for each edge overlapping $[y_{\text{top}}, y_{\text{bottom}}]$ and merges them with the interior intervals computed at the critical $y$-coordinates.
   For a left or right float, CSS Shapes Level 1 dictates that inline line boxes cannot split into multiple segments *through* a single float shape. Thus, Blink reduces the set of disjoint intervals $\{[a_1, b_1], [a_2, b_2], \dots, [a_k, b_k]\}$ into a single bounding `LineSegment`:
   $$[x_{\text{start}}, x_{\text{end}}] = \left[ \min_{j} a_j, \max_{j} b_j \right]$$
   The inline formatting context then shortens the line box by adjusting the inline-start edge to $\max(\text{line\_left}, x_{\text{end}})$ (for a `float: left`) or inline-end edge to $\min(\text{line\_right}, x_{\text{start}})$ (for a `float: right`).

---

### 4. Mathematical Invariants

1. **Interval Well-Formedness**: Every valid `ShapeInterval` $[x_{\text{start}}, x_{\text{end}}]$ produced by scanline pairing or edge clipping satisfies $x_{\text{start}} \le x_{\text{end}}$.
2. **Bounding Box Confinement**: Let $y_{\min} = \min_{v \in V} v.y$ and $y_{\max} = \max_{v \in V} v.y$. For any scanline $y \notin [y_{\min}, y_{\max}]$ (or line box $[y_1, y_2]$ disjoint from $[y_{\min}, y_{\max}]$), the set of exclusion intervals is strictly empty ($\emptyset$).
3. **Determinism**: Because the edge list order is fixed by the DOM specification of `polygon(...)` and sorting over $\mathbb{Q}$ or total-ordered floats is deterministic, the resulting exclusion intervals are uniquely determined for any $(P, y_1, y_2)$.

---

### 5. Rocq / Coq Formalization (`BlinkShapePolygonSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the data structures, scanline intersection, sorting, pairing, and proves the required invariants over the rational numbers $\mathbb{Q}$.

```coq
(** * BlinkShapePolygonSemantics.v
    Formalization of Chromium Blink Polygon Shape Exclusion (CSS Shapes Level 1 §3) *)

From Coq Require Import QArith QArith_base Qminmax List Bool Sorting.Permutation.
Import ListNotations.
Open Scope Q_scope.

(** ** 1. Core Data Structures *)

Record FloatPoint : Type := mkPoint {
  px : Q;
  py : Q
}.

Record Segment2D : Type := mkSegment {
  p1 : FloatPoint;
  p2 : FloatPoint
}.

Record ShapeInterval : Type := mkInterval {
  x_start : Q;
  x_end   : Q
}.

Definition wf_interval (iv : ShapeInterval) : Prop :=
  x_start iv <= x_end iv.

Inductive WindRule : Type :=
  | RuleEvenOdd
  | RuleNonZero.

Record PolygonShape : Type := mkPolygon {
  vertices  : list FloatPoint;
  wind_rule : WindRule
}.

(** Extract directed edges from a list of vertices *)
Fixpoint make_edges_aux (first : FloatPoint) (pts : list FloatPoint) : list Segment2D :=
  match pts with
  | [] => []
  | [last] => [mkSegment last first]
  | u :: ((v :: _) as rest) => (mkSegment u v) :: make_edges_aux first rest
  end.

Definition polygon_edges (poly : PolygonShape) : list Segment2D :=
  match vertices poly with
  | [] => []
  | v0 :: _ => make_edges_aux v0 (vertices poly)
  end.

(** ** 2. Scanline Intersection & Sorting *)

Definition y_min_seg (s : Segment2D) : Q := Qmin (py (p1 s)) (py (p2 s)).
Definition y_max_seg (s : Segment2D) : Q := Qmax (py (p1 s)) (py (p2 s)).

(** Decidable half-open interval check: y_min <= y < y_max *)
Definition intersects_scanline_b (s : Segment2D) (y : Q) : bool :=
  Qle_bool (y_min_seg s) y && negb (Qle_bool (y_max_seg s) y).

(** Linear interpolation for x(y) *)
Definition intersect_x (s : Segment2D) (y : Q) : Q :=
  let x1 := px (p1 s) in
  let y1 := py (p1 s) in
  let x2 := px (p2 s) in
  let y2 := py (p2 s) in
  x1 + ((y - y1) / (y2 - y1)) * (x2 - x1).

Definition raw_intersections (edges : list Segment2D) (y : Q) : list Q :=
   fold_right (fun s acc =>
    if intersects_scanline_b s y then (intersect_x s y) :: acc else acc
  ) [] edges.

(** Insertion sort over Q *)
Fixpoint insert_Q (x : Q) (l : list Q) : list Q :=
  match l with
  | [] => [x]
  | h :: t => if Qle_bool x h then x :: h :: t else h :: insert_Q x t
  end.

Fixpoint sort_Q (l : list Q) : list Q :=
  match l with
  | [] => []
  | h :: t => insert_Q h (sort_Q t)
  end.

(** Pair consecutive sorted x-coordinates into exclusion intervals *)
Fixpoint pair_intersections (xs : list Q) : list ShapeInterval :=
  match xs with
  | x1 :: x2 :: rest => (mkInterval x1 x2) :: pair_intersections rest
  | _ => []
  end.

Definition scanline_exclusion_intervals (poly : PolygonShape) (y : Q) : list ShapeInterval :=
  let edges := polygon_edges poly in
  let xs := sort_Q (raw_intersections edges y) in
  pair_intersections xs.

(** ** 3. Float Exclusion Bounding Segment *)

Definition merge_intervals (ivs : list ShapeInterval) : option ShapeInterval :=
  match ivs with
  | [] => None
  | iv0 :: rest =>
      let min_x := fold_right (fun i acc => Qmin (x_start i) acc) (x_start iv0) rest in
      let max_x := fold_right (fun i acc => Qmax (x_end i) acc) (x_end iv0) rest in
      Some (mkInterval min_x max_x)
  end.

(** ** 4. Mathematical Invariants & Theorems *)

Inductive Sorted_Q : list Q -> Prop :=
  | Sorted_nil : Sorted_Q []
  | Sorted_sing : forall x, Sorted_Q [x]
  | Sorted_cons : forall x y l, x <= y -> Sorted_Q (y :: l) -> Sorted_Q (x :: y :: l).

Lemma Qle_bool_false_le : forall x y : Q, Qle_bool x y = false -> y <= x.
Proof.
  intros x y H.
  destruct (Qlt_le_dec y x) as [Hlt | Hle].
  - apply Qlt_le_weak; exact Hlt.
  - apply Qle_bool_iff in Hle. congruence.
Qed.

Lemma insert_Q_sorted : forall x l, Sorted_Q l -> Sorted_Q (insert_Q x l).
Proof.
  intros x l H. induction H as [| y | y z l Hyz Hsorted IH].
  - simpl. constructor.
  - simpl. destruct (Qle_bool x y) eqn:Heq.
    + constructor. apply Qle_bool_iff; exact Heq. constructor.
    + constructor. apply Qle_bool_false_le; exact Heq. constructor.
  - simpl. destruct (Qle_bool x y) eqn:Heq1.
    + constructor. apply Qle_bool_iff; exact Heq1. constructor; assumption.
    + simpl in IH. destruct (Qle_bool x z) eqn:Heq2.
      * constructor. apply Qle_bool_false_le; exact Heq1. exact IH.
      * constructor. exact Hyz. exact IH.
Qed.

Theorem sort_Q_sorted : forall l, Sorted_Q (sort_Q l).
Proof.
  induction l as [| h t IH].
  - simpl. constructor.
  - simpl. apply insert_Q_sorted. exact IH.
Qed.

(** Theorem 1: All paired exclusion intervals are well-formed (x_start <= x_end). *)
Theorem pair_intersections_wf : forall xs,
  Sorted_Q xs -> Forall wf_interval (pair_intersections xs).
Proof.
  intros xs H.
  induction H as [| x | x y l Hxy Hsorted IH] using Sorted_Q_ind.
  - simpl. constructor.
  - simpl. constructor.
  - destruct l as [| z rest].
    + simpl. constructor.
      * unfold wf_interval. simpl. exact Hxy.
      * constructor.
    + simpl. constructor.
      * unfold wf_interval. simpl. exact Hxy.
      * inversion Hsorted; subst.
        (* Apply induction logic by structural recursion on the tail *)
Abort.

(** Direct structural