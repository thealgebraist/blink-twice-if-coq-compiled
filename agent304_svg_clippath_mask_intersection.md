**Agent 304: Audit Report — Chromium Blink SVG ClipPath and Mask Intersection**

### 1. Clip Rect Intersection: `rect_intersect(r1, r2)`
In Chromium Blink (`third_party/blink/renderer/platform/geometry/gfx/rect.h` and `third_party/blink/renderer/core/layout/svg/layout_svg_resource_clipper.cc`), SVG `clipPath` and `mask` bounding boxes are computed and intersected using axis-aligned bounding rectangles (`gfx::Rect` / `gfx::RectF`).

Given a rectangle defined by origin $(x, y)$ and non-negative dimensions $(w, h)$, let its bounding interval on the X-axis be $[x, x + w]$ and on the Y-axis be $[y, y + h]$. When intersecting `r1` and `r2`:
* $x' = \max(x_1, x_2)$
* $y' = \max(y_1, y_2)$
* $\text{right}' = \min(x_1 + w_1, x_2 + w_2)$
* $\text{bottom}' = \min(y_1 + h_1, y_2 + h_2)$
* $w' = \max(0, \text{right}' - x')$
* $h' = \max(0, \text{bottom}' - y')$

If the rectangles are disjoint ($x' > \text{right}'$ or $y' > \text{bottom}'$), clamping via $\max(0, \dots)$ prevents negative dimensions, collapsing the intersection width/height to $0$.

---

### 2. Invariants
For any well-formed rectangle `r1` where $w_1 \ge 0$ and $h_1 \ge 0$, intersecting `r1` with any arbitrary rectangle `r2` preserves the monotonic contraction invariant:
1. **Non-negativity:** $\text{width}(\text{rect\_intersect}(r_1, r_2)) \ge 0$ and $\text{height}(\text{rect\_intersect}(r_1, r_2)) \ge 0$.
2. **Width Bound:** $\text{width}(\text{rect\_intersect}(r_1, r_2)) \le \text{width}(r_1)$.
3. **Height Bound:** $\text{height}(\text{rect\_intersect}(r_1, r_2)) \le \text{height}(r_1)$.

In Blink's SVG rendering pipeline, this guarantees that applying consecutive `clip-path` and `mask` resources never expands the painted cull rect or visual overflow boundaries of an SVG element.

---

### 3. Concrete Rocq/Coq Formalization (`BlinkSVGClippathMaskIntersectionSemantics.v`)

The following file compiles cleanly in Coq/Rocq with zero `Admitted` statements.

```coq
(** * BlinkSVGClippathMaskIntersectionSemantics.v
    Agent 304 Audit: Chromium Blink SVG ClipPath and Mask Intersection Semantics.
    Zero admits. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Geometry Definitions *)

(** Representation of a 2D axis-aligned bounding rectangle (e.g., gfx::Rect). *)
Record Rect : Type := mkRect {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

(** A rectangle is well-formed if its width and height are non-negative. *)
Definition wf_rect (r : Rect) : Prop :=
  0 <= rw r /\ 0 <= rh r.

(** Right-most X coordinate of the rectangle. *)
Definition rect_right (r : Rect) : Z :=
  rx r + rw r.

(** Bottom-most Y coordinate of the rectangle. *)
Definition rect_bottom (r : Rect) : Z :=
  ry r + rh r.

(** Intersection of two rectangles, matching Blink's gfx::Rect::Intersect.
    Clamps negative spans to 0 for disjoint rectangles. *)
Definition rect_intersect (r1 r2 : Rect) : Rect :=
  let nx := Z.max (rx r1) (rx r2) in
  let ny := Z.max (ry r1) (ry r2) in
  let nright := Z.min (rect_right r1) (rect_right r2) in
  let nbottom := Z.min (rect_bottom r1) (rect_bottom r2) in
  let nw := Z.max 0 (nright - nx) in
  let nh := Z.max 0 (nbottom - ny) in
  mkRect nx ny nw nh.

(** Combined SVG ClipPath and Mask bounding box evaluation.
    Intersects the target local bounding box with both clipPath and mask bounds. *)
Definition svg_clip_and_mask_bounds (target clip mask : Rect) : Rect :=
  rect_intersect (rect_intersect target clip) mask.

(** ** 2. Invariant Theorems *)

(** Invariant 0: The intersection of any two rectangles is always well-formed
    (non-negative width and height), regardless of input well-formedness. *)
Theorem rect_intersect_wf : forall (r1 r2 : Rect),
  wf_rect (rect_intersect r1 r2).
Proof.
  intros r1 r2.
  unfold wf_rect, rect_intersect, rect_right, rect_bottom; simpl.
  lia.
Qed.

(** Invariant 1: Intersected width is bounded by the width of r1. *)
Theorem rect_intersect_width_le_r1 : forall (r1 r2 : Rect),
  0 <= rw r1 ->
  rw (rect_intersect r1 r2) <= rw r1.
Proof.
  intros r1 r2 Hw1.
  unfold rect_intersect, rect_right; simpl.
  lia.
Qed.

(** Invariant 2: Intersected height is bounded by the height of r1. *)
Theorem rect_intersect_height_le_r1 : forall (r1 r2 : Rect),
  0 <= rh r1 ->
  rh (rect_intersect r1 r2) <= rh r1.
Proof.
  intros r1 r2 Hh1.
  unfold rect_intersect, rect_bottom; simpl.
  lia.
Qed.

(** Symmetric Invariant: Intersected dimensions are also bounded by r2. *)
Theorem rect_intersect_dims_le_r2 : forall (r1 r2 : Rect),
  wf_rect r2 ->
  rw (rect_intersect r1 r2) <= rw r2 /\
  rh (rect_intersect r1 r2) <= rh r2.
Proof.
  intros r1 r2 [Hw2 Hh2].
  unfold rect_intersect, rect_right, rect_bottom; simpl.
  lia.
Qed.

(** Master Audit Theorem: Applying both SVG ClipPath and Mask intersection
    monotonically contracts (or preserves) the target bounding box dimensions
    and maintains well-formedness. *)
Theorem svg_clip_and_mask_invariants : forall (target clip mask : Rect),
  wf_rect target ->
  let res := svg_clip_and_mask_bounds target clip mask in
  wf_rect res /\
  rw res <= rw target /\
  rh res <= rh target.
Proof.
  intros target clip mask [Htw Hth] res.
  unfold res, svg_clip_and_mask_bounds.
  pose proof (rect_intersect_wf (rect_intersect target clip) mask) as Hwf.
  pose proof (rect_intersect_wf target clip) as [Hic_w Hic_h].
  pose proof (rect_intersect_width_le_r1 target clip Htw) as Hw1.
  pose proof (rect_intersect_height_le_r1 target clip Hth) as Hh1.
  pose proof (rect_intersect_width_le_r1 (rect_intersect target clip) mask Hic_w) as Hw2.
  pose proof (rect_intersect_height_le_r1 (rect_intersect target clip) mask Hic_h) as Hh2.
  split; [exact Hwf | split; lia].
Qed.
```