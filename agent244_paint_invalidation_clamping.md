### 1. Clamping Mechanics in Chromium Blink
During the PrePaint and PaintInvalidation phases in Chromium Blink (`third_party/blink/renderer/core/paint/paint_invalidator.cc`), layout objects compute dirty rectangles (`dirty_rect`) representing visual changes that require raster invalidation. 

To prevent out-of-bounds rasterization and infinite layer expansion (e.g., caused by layout overflow, massive transforms, or `LayoutUnit::Max()` sentinel values), the `dirty_rect` is clamped to the physical coordinate bounds of its backing composited layer (`layer_bounds`). This clamping operation is defined as the geometric intersection:

$$\text{invalidation\_rect} = \text{intersect}(\text{dirty\_rect}, \text{layer\_bounds})$$

If the intersection is degenerate (i.e., the rectangles are disjoint), the clamping operation normalizes the resulting rectangle to the canonical empty rectangle at the origin `(0, 0, 0, 0)` to ensure non-negative dimensions and prevent integer underflow in subsequent damage tracking passes.

---

### 2. Core Invariants
1. **Non-Negativity Invariant**: For any arbitrary input `dirty_rect` and `layer_bounds`, the resulting `invalidation_rect` always has `width >= 0` and `height >= 0`.
2. **Subset (Containment) Invariant**: Every spatial point $(px, py)$ contained within `invalidation_rect` is guaranteed to be contained within `layer_bounds` (and `dirty_rect`).
3. **Bounding Box Subset Invariant**: If `invalidation_rect` is non-empty, its bounding intervals $[x, x+w]$ and $[y, y+h]$ are sub-intervals of `layer_bounds`.
4. **Idempotence Invariant**: Clamping an already clamped `invalidation_rect` against the same `layer_bounds` yields the exact same rectangle.

---

### 3. Concrete Rocq/Coq Formalization

Below is the complete, self-contained formalization for `BlinkPaintInvalidationClampingSemantics.v` using `ZArith` and `Lia`, containing **0 admits**.

```coq
(** * BlinkPaintInvalidationClampingSemantics.v
    Formal verification of Chromium Blink Paint Invalidation Rect Clamping
    Agent 244 Audit Artifact *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Geometric Primitives (gfx::Rect / PhysicalRect) *)

Record Rect : Type := mkRect {
  x : Z;
  y : Z;
  width : Z;
  height : Z
}.

Definition right (r : Rect) : Z := r.(x) + r.(width).
Definition bottom (r : Rect) : Z := r.(y) + r.(height).

(** Well-formedness: dimensions must be non-negative *)
Definition wf_rect (r : Rect) : Prop :=
  r.(width) >= 0 /\ r.(height) >= 0.

(** Empty check: matches gfx::Rect::IsEmpty() *)
Definition is_empty (r : Rect) : Prop :=
  r.(width) <= 0 \/ r.(height) <= 0.

Definition is_empty_b (r : Rect) : bool :=
  (r.(width) <=? 0) || (r.(height) <=? 0).

(** Point containment: half-open interval [x, x + width) x [y, y + height) *)
Definition contains_point (r : Rect) (px py : Z) : Prop :=
  r.(x) <= px < right r /\ r.(y) <= py < bottom r.

(** Geometric subset based on point containment *)
Definition rect_subset (r1 r2 : Rect) : Prop :=
  forall px py : Z, contains_point r1 px py -> contains_point r2 px py.

(** Bounding box containment: strong structural subset for non-empty rects *)
Definition bounds_subset (r1 r2 : Rect) : Prop :=
  (~ is_empty r1) ->
  r2.(x) <= r1.(x) /\ right r1 <= right r2 /\
  r2.(y) <= r1.(y) /\ bottom r1 <= bottom r2.

(** ** 2. Clamping and Intersection Mechanics *)

Definition empty_rect : Rect := mkRect 0 0 0 0.

(** Raw intersection calculation prior to empty normalization *)
Definition raw_intersect (r1 r2 : Rect) : Rect :=
  let rx := Z.max r1.(x) r2.(x) in
  let ry := Z.max r1.(y) r2.(y) in
  let rr := Z.min (right r1) (right r2) in
  let rb := Z.min (bottom r1) (bottom r2) in
  mkRect rx ry (Z.max 0 (rr - rx)) (Z.max 0 (rb - ry)).

(** Canonical intersection: normalizes empty results to (0,0,0,0) 
    Matches Chromium's gfx::Rect::Intersect behavior. *)
Definition intersect (r1 r2 : Rect) : Rect :=
  let raw := raw_intersect r1 r2 in
  if is_empty_b raw then empty_rect else raw.

(** Blink Paint Invalidation Clamping Operation *)
Definition clamp_invalidation_rect (dirty_rect layer_bounds : Rect) : Rect :=
  intersect dirty_rect layer_bounds.

(** ** 3. Helper Lemmas *)

Lemma is_empty_b_spec : forall r,
  is_empty_b r = true <-> is_empty r.
Proof.
  intros r. unfold is_empty_b, is_empty.
  rewrite orb_true_iff.
  rewrite Z.leb_le, Z.leb_le.
  reflexivity.
Qed.

Lemma is_empty_b_false : forall r,
  is_empty_b r = false <-> r.(width) > 0 /\ r.(height) > 0.
Proof.
  intros r. unfold is_empty_b.
  rewrite orb_false_iff.
  rewrite Z.leb_gt, Z.leb_gt.
  lia.
Qed.

Lemma empty_rect_no_points : forall px py,
  ~ contains_point empty_rect px py.
Proof.
  intros px py. unfold contains_point, empty_rect, right, bottom; simpl.
  lia.
Qed.

(** ** 4. Verification of Audit Invariants *)

(** Invariant 1: invalidation_rect width and height are always >= 0 *)
Theorem clamp_invalidation_rect_non_negative :
  forall (dirty_rect layer_bounds : Rect),
  wf_rect (clamp_invalidation_rect dirty_rect layer_bounds).
Proof.
  intros dirty_rect layer_bounds.
  unfold clamp_invalidation_rect, intersect, raw_intersect, wf_rect.
  destruct (is_empty_b _) eqn:Heq; simpl; lia.
Qed.

(** Invariant 2a: invalidation_rect is a point-wise subset of layer_bounds *)
Theorem clamp_invalidation_rect_subset_layer :
  forall (dirty_rect layer_bounds : Rect),
  rect_subset (clamp_invalidation_rect dirty_rect layer_bounds) layer_bounds.
Proof.
  intros dirty_rect layer_bounds px py Hcont.
  unfold clamp_invalidation_rect, intersect in Hcont.
  destruct (is_empty_b (raw_intersect dirty_rect layer_bounds)) eqn:Hemp.
  - exfalso. apply (empty_rect_no_points px py Hcont).
  - apply is_empty_b_false in Hemp.
    unfold raw_intersect, contains_point, right, bottom in *; simpl in *.
    destruct dirty_rect as [dx dy dw dh].
    destruct layer_bounds as [lx ly lw lh].
    simpl in *.
    lia.
Qed.

(** Invariant 2b: invalidation_rect is a point-wise subset of dirty_rect *)
Theorem clamp_invalidation_rect_subset_dirty :
  forall (dirty_rect layer_bounds : Rect),
  rect_subset (clamp_invalidation_rect dirty_rect layer_bounds) dirty_rect.
Proof.
  intros dirty_rect layer_bounds px py Hcont.
  unfold clamp_invalidation_rect, intersect in Hcont.
  destruct (is_empty_b (raw_intersect dirty_rect layer_bounds)) eqn:Hemp.
  - exfalso. apply (empty_rect_no_points px py Hcont).
  - apply is_empty_b_false in Hemp.
    unfold raw_intersect, contains_point, right, bottom in *; simpl in *.
    destruct dirty_rect as [dx dy dw dh].
    destruct layer_bounds as [lx ly lw lh].
    simpl in *.
    lia.
Qed.

(** Invariant 2c: Point containment in clamped rect is exact conjunction *)
Theorem clamp_invalidation_rect_point_iff :
  forall (dirty_rect layer_bounds : Rect) (px py : Z),
  contains_point (clamp_invalidation_rect dirty_rect layer_bounds) px py <->
  (contains_point dirty_rect px py /\ contains_point layer_bounds px py).
Proof.
  intros dirty_rect layer_bounds px py. split.
  - intros H. split.
    + apply (clamp_invalidation_rect_subset_dirty dirty_rect layer_bounds px py H).
    + apply (clamp_invalidation_rect_subset_layer dirty_rect layer_bounds px py H).
  - intros [Hd Hl].
    unfold clamp_invalidation_rect, intersect.
    destruct (is_empty_b (raw_intersect dirty_rect layer_bounds)) eqn:Hemp.
    + apply is_empty_b_spec in Hemp.
      unfold is_empty, raw_intersect, contains_point, right, bottom in *; simpl in *.
      lia.
    + unfold raw_intersect, contains_point, right, bottom in *; simpl in *.
      lia.
Qed.

(** Invariant 3: Bounding coordinates of non-empty invalidation_rect are within layer_bounds *)
Theorem clamp_invalidation_rect_bounds_subset :
  forall (dirty_rect layer_bounds : Rect),
  bounds_subset (clamp_invalidation_rect dirty_rect layer_bounds) layer_bounds.
Proof.
  intros dirty_rect layer_bounds Hnot_empty.
  unfold clamp_invalidation_rect, intersect in *.
  destruct (is_empty_b (raw_intersect dirty_rect layer_bounds)) eqn:Hemp.
  - exfalso. apply Hnot_empty. unfold is_empty, empty_rect; simpl; lia.
  - apply is_empty_b_false in Hemp.
    unfold raw_intersect, right, bottom in *; simpl in *.
    lia.
Qed.

(** Invariant 4: Clamping is idempotent with respect to layer_bounds *)
Theorem clamp_invalidation_rect_idempotent :
  forall (dirty_rect layer_bounds : Rect),
  clamp_invalidation_rect (clamp_invalidation_rect dirty_rect layer_bounds) layer_bounds =
  clamp_invalidation_rect dirty_rect layer_bounds.
Proof.
  intros dirty_rect layer_bounds.
  unfold clamp_invalidation_rect, intersect.
  destruct (is_empty_b (raw_intersect dirty_rect layer_bounds)) eqn:Hemp1.
  - unfold raw_intersect at 1; simpl.
    destruct (is_empty_b _) eqn:Hemp2.
    + reflexivity.
    + apply is_empty_b_false in Hemp2. simpl in Hemp2. lia.
  - apply is_empty_b_false in Hemp1.
    destruct (is_empty_b (raw_intersect (raw_intersect dirty_rect layer_bounds) layer_bounds)) eqn:Hemp2.
    + apply is_empty_b_spec in Hemp2.
      unfold raw_intersect, is_empty, right, bottom in *; simpl in *.
      lia.
    + unfold raw_intersect, right, bottom in *; simpl in *.
      f_equal; lia.
Qed.
```