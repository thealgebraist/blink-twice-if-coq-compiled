### Audit Report: Chromium Blink Overflow Clip Geometry vs. CSS Overflow 3 §3

**Auditor:** Agent 238  
**Target:** Chromium Blink Layout / Paint Clip Geometry (`PhysicalRect::Intersect`)  
**Specification:** CSS Overflow Module Level 3, §3 (Overflow Concepts & Clipping)  

---

#### 1. Rect Intersection Semantics
In CSS Overflow 3 §3, the overflow clip edge establishes a rectangular clipping region (the *clip rect*). When painting or hit-testing an element's overflow, the scrollable or visible content area (the *content rect*) is restricted to the intersection of the content rect and the clip rect.

In Chromium Blink (specifically within `third_party/blink/renderer/platform/geometry/physical_rect.h` and `gfx::Rect`), 2D axis-aligned rectangles are represented by an origin $(x, y)$ and dimensions $(w, h)$, or equivalently as intervals along the X and Y axes: $[x_1, r_1] \times [y_1, b_1]$, where $r_1 = x_1 + w_1$ and $b_1 = y_1 + h_1$.

The 1D interval intersection for each axis is computed as:
$$\text{ left } = \max(x_1, x_2), \quad \text{ right } = \min(r_1, r_2)$$
$$\text{ width } = \max(0, \text{right} - \text{left})$$

If $\text{left} \ge \text{right}$ on either axis, the resulting intersection is degenerate (empty), and Blink normalizes the rectangle's dimensions to zero.

#### 2. Verified Invariants
1. **Containment Invariant:** For any content rectangle $R_1$ and clip rectangle $R_2$, every point $p = (px, py)$ within the intersected rectangle $R_1 \cap R_2$ is strictly contained within the bounds of the clip rectangle $R_2$ (and $R_1$).
2. **Disjoint Empty Invariant:** If $R_1$ and $R_2$ are geometrically disjoint (i.e., $r_1 \le x_2 \lor r_2 \le x_1$ on the X-axis, or $b_1 \le y_2 \lor b_2 \le y_1$ on the Y-axis), the resulting intersection rectangle is guaranteed to be empty (area/dimensions equal to 0, containing no points).

---

#### 3. Formal Verification (`BlinkOverflowClipGeometrySemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization proving the geometry invariants with zero admits.

```coq
(** 
 * File: BlinkOverflowClipGeometrySemantics.v
 * Auditor: Agent 238
 * Target: Chromium Blink Overflow Clip Geometry vs CSS Overflow 3 §3
 *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** * 1. 1D Interval Geometry ([x, r]) *)

Record Interval : Type := mkInterval {
  x : Z;
  r : Z
}.

(** An interval is empty if its right edge is less than or equal to its left edge. *)
Definition is_empty_interval (i : Interval) : Prop :=
  i.(r) <= i.(x).

(** Point containment in a half-open 1D interval [x, r). 
    Standard layout engines (Blink/Skia) treat pixel bounds [x, r) as half-open. *)
Definition in_interval (p : Z) (i : Interval) : Prop :=
  i.(x) <= p < i.(r).

(** Two intervals are disjoint if one ends before or at the start of the other. *)
Definition disjoint_interval (i1 i2 : Interval) : Prop :=
  i1.(r) <= i2.(x) \/ i2.(r) <= i1.(x).

(** 1D Intersection: [max(x1, x2), min(r1, r2)] *)
Definition intersect_interval (i1 i2 : Interval) : Interval :=
  mkInterval (Z.max i1.(x) i2.(x)) (Z.min i1.(r) i2.(r)).

(** Interval containment: i1 is a sub-interval of i2 if all points in i1 are in i2. *)
Definition interval_contained (i1 i2 : Interval) : Prop :=
  forall p : Z, in_interval p i1 -> in_interval p i2.


(** * 2. 1D Interval Theorems *)

Theorem intersect_interval_contained_left :
  forall i1 i2 : Interval,
  interval_contained (intersect_interval i1 i2) i1.
Proof.
  unfold interval_contained, in_interval, intersect_interval; simpl.
  intros i1 i2 p H.
  lia.
Qed.

Theorem intersect_interval_contained_right :
  forall i1 i2 : Interval,
  interval_contained (intersect_interval i1 i2) i2.
Proof.
  unfold interval_contained, in_interval, intersect_interval; simpl.
  intros i1 i2 p H.
  lia.
Qed.

Theorem intersect_interval_empty_when_disjoint :
  forall i1 i2 : Interval,
  disjoint_interval i1 i2 ->
  is_empty_interval (intersect_interval i1 i2).
Proof.
  unfold disjoint_interval, is_empty_interval, intersect_interval; simpl.
  intros i1 i2 H.
  lia.
Qed.

Theorem empty_interval_has_no_points :
  forall (i : Interval) (p : Z),
  is_empty_interval i -> ~ in_interval p i.
Proof.
  unfold is_empty_interval, in_interval, not.
  intros i p H_empty H_in.
  lia.
Qed.


(** * 3. 2D Rectangle Geometry (Blink PhysicalRect / CSS Clip Region) *)

Record Rect : Type := mkRect {
  horiz : Interval;
  vert  : Interval
}.

(** A 2D rectangle is empty if either its horizontal or vertical interval is empty. *)
Definition is_empty_rect (rect : Rect) : Prop :=
  is_empty_interval rect.(horiz) \/ is_empty_interval rect.(vert).

(** Point (px, py) containment in a 2D rectangle. *)
Definition in_rect (px py : Z) (rect : Rect) : Prop :=
  in_interval px rect.(horiz) /\ in_interval py rect.(vert).

(** Two rectangles are disjoint if they are disjoint on at least one axis. *)
Definition disjoint_rect (r1 r2 : Rect) : Prop :=
  disjoint_interval r1.(horiz) r2.(horiz) \/
  disjoint_interval r1.(vert) r2.(vert).

(** 2D Rect intersection (Content Rect intersected with Overflow Clip Rect). *)
Definition intersect_rect (content_rect clip_rect : Rect) : Rect :=
  mkRect (intersect_interval content_rect.(horiz) clip_rect.(horiz))
         (intersect_interval content_rect.(vert) clip_rect.(vert)).

(** Rect containment: r1 is contained within r2. *)
Definition rect_contained (r1 r2 : Rect) : Prop :=
  forall px py : Z, in_rect px py r1 -> in_rect px py r2.


(** * 4. Main Audit Invariants (CSS Overflow 3 §3) *)

(** Invariant 1a: The intersection rect is always contained within the clip rect. *)
Theorem intersection_contained_in_clip_rect :
  forall (content_rect clip_rect : Rect),
  rect_contained (intersect_rect content_rect clip_rect) clip_rect.
Proof.
  unfold rect_contained, in_rect, intersect_rect; simpl.
  intros content_rect clip_rect px py [Hx Hy].
  split.
  - apply (intersect_interval_contained_right content_rect.(horiz) clip_rect.(horiz) px Hx).
  - apply (intersect_interval_contained_right content_rect.(vert) clip_rect.(vert) py Hy).
Qed.

(** Invariant 1b: The intersection rect is also contained within the content rect. *)
Theorem intersection_contained_in_content_rect :
  forall (content_rect clip_rect : Rect),
  rect_contained (intersect_rect content_rect clip_rect) content_rect.
Proof.
  unfold rect_contained, in_rect, intersect_rect; simpl.
  intros content_rect clip_rect px py [Hx Hy].
  split.
  - apply (intersect_interval_contained_left content_rect.(horiz) clip_rect.(horiz) px Hx).
  - apply (intersect_interval_contained_left content_rect.(vert) clip_rect.(vert) py Hy).
Qed.

(** Invariant 2a: The intersection rect is empty when the content and clip rects are disjoint. *)
Theorem intersection_empty_when_disjoint :
  forall (content_rect clip_rect : Rect),
  disjoint_rect content_rect clip_rect ->
  is_empty_rect (intersect_rect content_rect clip_rect).
Proof.
  unfold disjoint_rect, is_empty_rect, intersect_rect; simpl.
  intros content_rect clip_rect [H_horiz | H_vert].
  - left. apply intersect_interval_empty_when_disjoint. exact H_horiz.
  - right. apply intersect_interval_empty_when_disjoint. exact H_vert.
Qed.

(** Invariant 2b: An empty intersection rect contains no visible/clickable points. *)
Theorem disjoint_intersection_contains_no_points :
  forall (content_rect clip_rect : Rect) (px py : Z),
  disjoint_rect content_rect clip_rect ->
  ~ in_rect px py (intersect_rect content_rect clip_rect).
Proof.
  intros content_rect clip_rect px py H_disj H_in.
  pose proof (intersection_empty_when_disjoint content_rect clip_rect H_disj) as H_empty.
  unfold is_empty_rect in H_empty.
  unfold in_rect in H_in.
  destruct H_in as [H_in_x H_in_y].
  destruct H_empty as [H_emp_x | H_emp_y].
  - apply (empty_interval_has_no_points _ px H_emp_x H_in_x).
  - apply (empty_interval_has_no_points _ py H_emp_y H_in_y).
Qed.

(** * 5. Blink Normalization Equivalence (Width/Height clamping to 0) *)

(** Blink's PhysicalRect::Intersect clamps width/height to 0 when empty, resetting origin if needed. 
    We show that clamping r' = max(x', r') preserves the exact point-set semantics. *)
Definition normalize_interval (i : Interval) : Interval :=
  mkInterval i.(x) (Z.max i.(x) i.(r)).

Theorem normalize_preserves_points :
  forall (i : Interval) (p : Z),
  in_interval p (normalize_interval i) <-> in_interval p i.
Proof.
  unfold in_interval, normalize_interval; simpl.
  intros i p.
  split; intro H; lia.
Qed.
```