# Agent 125 Audit Report: Chromium Blink Overflow Clipping vs. CSS Overflow Module Level 3 §3

**Target Specification:** CSS Overflow Module Level 3, §3 (Overflow Concepts and Clipping)  
**Target Implementation:** Chromium Blink (`third_party/blink/renderer/core/layout/`, `third_party/blink/renderer/core/paint/`)

---

## 1. Clip Rect Computation for `overflow: hidden` Based on Padding Box

### CSS Overflow 3 §3 Specification
Per CSS Overflow 3 §3.2, when `overflow-x` or `overflow-y` computes to `hidden` (or `clip`, `scroll`, `auto`), the element establishes an overflow clip edge. Unless modified by `overflow-clip-margin`, the clipping region for `overflow: hidden` is strictly the **padding box** of the box. Furthermore, if the box has scrollable overflow, `overflow: hidden` still establishes a scroll container (allowing programmatic scrolling via `scrollTo()`), whereas `overflow: clip` forbids programmatic scrolling entirely.

### Chromium Blink Implementation
In Blink’s LayoutNG / PaintPropertyTreeBuilder architecture (`box_paint_property_tree_builder.cc` & `layout_box.cc`), the overflow clip rect is computed during the PrePaint lifecycle phase via `LayoutBox::OverflowClipRect`.

1. **Base Geometry:** Blink begins with the PhysicalBorderBoxRect and subtracts the computed physical border widths (`BorderTop()`, `BorderRight()`, `BorderBottom()`, `BorderLeft()`) to derive the `PhysicalPaddingBoxRect()`.
2. **Scrollbar Exclusion:** If scrollbars are present (not applicable to `hidden`, which suppresses visual scrollbars, though `OverlayScrollbarClipBehavior` can interact in edge cases), their thickness is subtracted from the padding box.
3. **Axis-Specific Clipping:** Blink computes `OverflowClipAxes` (`kNoOverflowClip`, `kOverflowClipX`, `kOverflowClipY`, `kOverflowClipBoth`). If `overflow-x: hidden` and `overflow-y: visible` occurs, CSS Overflow 3 §3.2 mandates that `visible` computes to `auto` (or `clip` if paired with `clip`). Thus, `hidden` forces both axes to clip in standard layout boxes, making the clip rect precisely the 2D `PhysicalPaddingBoxRect`.
4. **Subpixel Snapping:** During paint property tree updates (`FragmentPaintPropertyTreeBuilder::UpdateOverflowClip`), the `PhysicalRect` (represented in `LayoutUnit`, 1/64th of a pixel) is converted to a `gfx::RectF` (generally pixel-snapped via `ToSnappedClipRect` unless animated/transformed) and injected into the `ClipPaintPropertyNode`.

---

## 2. Ink Overflow vs. Scrollable Overflow Containment

### CSS Overflow 3 §3.1 Specification
CSS Overflow 3 bifurcates overflow into two distinct geometric models:
* **Ink Overflow (§3.1.1):** The painting effects of a box and its descendants that extend outside the border box, which do not affect layout or extend the scrollable area. Examples include `box-shadow`, `text-shadow`, `outline`, border-image-outset, and glyph bounds exceeding the font ascent/descent.
* **Scrollable Overflow (§3.1.2):** The union of the box's padding box and the margin/border boxes of its in-flow and positioned descendants (transformed appropriately), which triggers scrollbars and defines the scrollable range.

### Chromium Blink Implementation
Blink maintains dual overflow structures on `PhysicalBoxFragment` and `LayoutBox` (managed via `InkOverflow` and `LayoutOverflow` classes):

1. **Scrollable Overflow (`LayoutOverflow`):**
   * Calculated during layout fragment construction (`LayoutOverflowCalculator`).
   * Stored on the fragment as a `PhysicalRect`.
   * Initialized directly to the `PaddingBoxRect()`.
   * Expanded by adding the layout bounds of child fragments (adjusted by relative positioning and transforms).
   * **Containment Rule:** When a child itself has `overflow != visible` (i.e., `IsScrollContainer()` or `ShouldClipOverflowAlongBothAxes()`), its own scrollable overflow and ink overflow are **not** propagated to the parent's `LayoutOverflow`. Only the child's border box (and specified margins) contributes to the parent's scrollable overflow.

2. **Ink Overflow (`InkOverflow`):**
   * Computed post-layout (often lazily during PrePaint/PaintInvalidation) from the `PhysicalBoxFragment`.
   * Tracks `self_ink_overflow` (e.g., box shadows on the element itself) and `contents_ink_overflow` (union of children's visual overflow).
   * **Containment Rule:** If a box has `overflow: hidden` (establishing `kOverflowClipBoth`), its `contents_ink_overflow` is completely suppressed/clipped at the `OverflowClipRect` (the padding box). The box’s `self_ink_overflow` (such as an outset `box-shadow` or `outline` applied to the container itself) is painted *outside* the `OverflowClipPaintPropertyNode` in the paint tree, and therefore is **not** clipped by the box's own `overflow: hidden`.

---

## 3. Core Verification Invariants

To formally verify Blink's overflow clipping semantics against CSS Overflow 3 §3, we establish two fundamental geometric invariants:

1. **Invariant I (Scrollable Overflow Padding-Box Monotonicity):**  
   For any layout box, its computed scrollable overflow region (`LayoutOverflowRect`) is a superset of its padding box (`PaddingBoxRect`). Even if descendants have negative margins or are positioned entirely outside the box in the negative coordinate space, the scrollable origin/bounds anchor to and strictly encompass the padding box.
   $$\forall b \in \text{Box},\quad \text{PaddingBox}(b) \subseteq \text{ScrollableOverflow}(b)$$

2. **Invariant II (Clipped Paint Region Containment):**  
   For any layout box $b$ with `overflow: hidden`, the painted contents region (comprising the union of descendant border boxes, descendant scrollable overflows, and descendant ink overflows, denoted $\text{ContentsVisualOverflow}(b)$) after passing through the `OverflowClip` property node is strictly contained within the computed `OverflowClipRect(b)` (the padding box). Self ink overflow ($\text{SelfInkOverflow}(b)$) bypasses this clip.
   $$\forall b \in \text{Box},\quad \text{overflow}(b) = \text{Hidden} \implies \text{ClippedContents}(b) \subseteq \text{OverflowClipRect}(b) = \text{PaddingBox}(b)$$

---

## 4. Formal Verification in Rocq (Coq): `BlinkOverflowClippingSemantics.v`

The following file provides a self-contained, zero-admitted formalization of Blink's 2D physical geometry (`LayoutUnit` abstracted over $\mathbb{Z}$), box geometry, overflow models, and proofs of the core invariants.

```coq
(** * BlinkOverflowClippingSemantics.v
    Formal Audit of Chromium Blink Overflow Clipping vs. CSS Overflow Module Level 3 §3
    Agent 125 Verification Artifact *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Fundamental 2D Geometry (Blink PhysicalRect / LayoutUnit Model) *)

(** A 2D physical rectangle defined by min/max coordinates (left, top, right, bottom).
    In Blink, PhysicalRect uses (offset_x, offset_y, width, height) with width >= 0, height >= 0.
    Representing as bounding intervals [x1, x2] x [y1, y2] simplifies set-inclusion proofs. *)
Record PhysicalRect : Type := mkRect {
  x1 : Z;
  y1 : Z;
  x2 : Z;
  y2 : Z;
  wf_x : x1 <= x2;
  wf_y : y1 <= y2
}.

(** Point-in-rectangle predicate *)
Definition in_rect (px py : Z) (r : PhysicalRect) : Prop :=
  r.(x1) <= px <= r.(x2) /\ r.(y1) <= py <= r.(y2).

(** Rectangle containment (subset relation) *)
Definition rect_subset (r1 r2 : PhysicalRect) : Prop :=
  forall px py : Z, in_rect px py r1 -> in_rect px py r2.

(** Bounding-coordinate characterization of subset *)
Lemma rect_bounds_subset : forall r1 r2 : PhysicalRect,
  r2.(x1) <= r1.(x1) ->
  r1.(x2) <= r2.(x2) ->
  r2.(y1) <= r1.(y1) ->
  r1.(y2) <= r2.(y2) ->
  rect_subset r1 r2.
Proof.
  intros r1 r2 Hx1 Hx2 Hy1 Hy2 px py [Hpx Hpy].
  unfold in_rect in *.
  split; lia.
Qed.

Lemma rect_subset_refl : forall r : PhysicalRect, rect_subset r r.
Proof.
  intros r px py H. exact H.
Qed.

Lemma rect_subset_trans : forall r1 r2 r3 : PhysicalRect,
  rect_subset r1 r2 -> rect_subset r2 r3 -> rect_subset r1 r3.
Proof.
  intros r1 r2 r3 H12 H23 px py H1.
  apply H23. apply H12. exact H1.
Qed.

(** Union of two PhysicalRects (Blink's PhysicalRect::Unite) *)
Program Definition rect_union (r1 r2 : PhysicalRect) : PhysicalRect :=
  {| x1 := Z.min r1.(x1) r2.(x1);
     y1 := Z.min r1.(y1) r2.(y1);
     x2 := Z.max r1.(x2) r2.(x2);
     y2 := Z.max r1.(y2) r2.(y2) |}.
Next Obligation.
  pose proof r1.(wf_x). pose proof r2.(wf_x). lia.
Qed.
Next Obligation.
  pose proof r1.(wf_y). pose proof r2.(wf_y). lia.
Qed.

Lemma rect_union_subset_l : forall r1 r2 : PhysicalRect,
  rect_subset r1 (rect_union r1 r2).
Proof.
  intros r1 r2.
  apply rect_bounds_subset; simpl; lia.
Qed.

Lemma rect_union_subset_r : forall r1 r2 : PhysicalRect,
  rect_subset r2 (rect_union r1 r2).
Proof.
  intros r1 r2.
  apply rect_bounds_subset; simpl; lia.
Qed.

(** Intersection of two PhysicalRects, clamped to remain well-formed if disjoint
    (Blink's PhysicalRect::Intersect / clip clamping) *)
Program Definition rect_intersect (target clip : PhysicalRect) : PhysicalRect :=
  let nx1 := Z.min clip.(x2) (Z.max target.(x1) clip.(x1)) in
  let ny1 := Z.min clip.(y2) (Z.max target.(y1) clip.(y1)) in
  let nx2 := Z.max clip.(x1) (Z.min target.(x2) clip.(x2)) in
  let ny2 := Z.max clip.(y1) (Z.min target.(y2) clip.(y2)) in
  {| x1 := Z.min nx1 nx2;
     y1 := Z.min ny1 ny2;
     x2 := Z.max nx1 nx2;
     y2 := Z.max ny1 ny2 |}.
Next Obligation. lia. Qed.
Next Obligation. lia. Qed.

Lemma rect_intersect_in_clip : forall target clip : PhysicalRect,
  rect_subset (rect_intersect target clip) clip.
Proof.
  intros target clip.
  pose proof clip.(wf_x). pose proof clip.(wf_y).
  pose proof target.(wf_x). pose proof target.(wf_y).
  apply rect_bounds_subset; simpl; lia.
Qed.

(** ** 2. CSS Overflow 3 & Blink Box Model Definitions *)

Inductive OverflowStyle : Type :=
  | OverflowVisible
  | OverflowHidden
  | OverflowClip
  | OverflowScroll
  | OverflowAuto.

(** Determines if an overflow style establishes an overflow clip edge (CSS Overflow 3 §3.2) *)
Definition clips_overflow (s : OverflowStyle) : bool :=
  match s with
  | OverflowVisible => false
  | _ => true
  end.

(** Border Outsets / Insets (non-negative border thicknesses) *)
Record BorderWidths : Type := mkBorders {
  b_top : Z;
  b_right : Z;
  b_bottom : Z;
  b_left : Z;
  wf_bt : 0 <= b_top;
  wf_br : 0 <= b_right;
  wf_bb : 0 <= b_bottom;
  wf_bl : 0 <= b_left
}.

(** Child overflow contribution representation *)
Record ChildFragment : Type := mkChild {
  child_border_box : PhysicalRect;
  child_scrollable_overflow : PhysicalRect;
  child_ink_overflow : PhysicalRect;
  child_overflow_style : OverflowStyle
}.

(** Blink LayoutBox / PhysicalBoxFragment abstraction *)
Record LayoutBox : Type := mkBox {
  padding_box : PhysicalRect;
  borders : BorderWidths;
  overflow_style : OverflowStyle;
  self_ink_overflow : PhysicalRect; (** e.g. outset box-shadow on the box itself *)
  children : list ChildFragment;
  (** Invariant that self_ink_overflow encompasses at least the padding box *)
  wf_self_ink : rect_subset padding_box self_ink_overflow
}.

(** Border box computed by expanding the padding box by border widths *)
Program Definition compute_border_box (b : LayoutBox) : PhysicalRect :=
  {| x1 := b.(padding_box).(x1) - b.(borders).(b_left);
     y1 := b.(padding_box).(y1) - b.(borders).(b_top);
     x2 := b.(padding_box).(x2) + b.(borders).(b_right);
     y2 := b.(padding_box).(y2) + b.(borders).(b_bottom) |}.
Next Obligation.
  pose proof b.(padding_box).(wf_x).
  pose proof b.(borders).(wf_bl).
  pose proof b.(borders).(wf_br).
  lia.
Qed.
Next Obligation.
  pose proof b.(padding_box).(wf_y).
  pose proof b.(borders).(wf_bt).
  pose proof b.(borders).(wf_bb).
  lia.
Qed.

Theorem padding_box_inside_border_box : forall b : LayoutBox,
  rect_subset b.(padding_box) (compute_border_box b).
Proof.
  intros b.
  pose proof b.(borders).(wf_bl).
  pose proof b.(borders).(wf_br).
  pose proof b.(borders).(wf_bt).
  