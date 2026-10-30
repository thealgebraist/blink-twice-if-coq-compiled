### Architectural & Specification Audit: Agent 252
**Target:** Chromium Blink Outline Geometry (`third_party/blink/renderer/core/paint/outline_painter.cc`, `layout_box.cc`) vs. CSS 2.1 §18.4 (Dynamic Outlines: the `'outline'` property) & CSS UI 3 §4.4 (`'outline-offset'`).

---

### 1. Outline Rect Expansion Semantics

In Chromium Blink's Paint and Layout NG pipelines, outlines are drawn completely outside the normal box model flow. Let the reference frame be the local coordinate space of a `LayoutBox` (or `PhysicalBoxFragment`), where the **Border Box** is defined by the tuple $B = (x, y, w, h)$ with $w \ge 0$ and $h \ge 0$.

Given:
* `outline_width` ($\omega \in \mathbb{Z}$, with CSS constraint $\omega \ge 0$)
* `outline_offset` ($\delta \in \mathbb{Z}$, unrestricted sign per CSS UI 3, though non-negative in strict CSS 2.1 geometry)

The total scalar expansion $E$ applied to each edge of the border box to determine the **Outer Outline Rect** $O_{ext}$ is:
$$E = \omega + \delta$$

In Blink (`OutlinePainter::PaintOutline` and `LayoutObject::OutlineRects`), the border box is inflated outward by $E$ in all four cardinal directions:
$$\begin{aligned}
O_{x} &= x - (\omega + \delta) \\
O_{y} &= y - (\omega + \delta) \\
O_{w} &= w + 2(\omega + \delta) \\
O_{h} &= h + 2(\omega + \delta)
\end{aligned}$$

*(Note: When $O_w < 0$ or $O_h < 0$ due to a large negative `outline-offset`, Blink clamps dimensions or degenerates the path, whereas for standard non-negative offsets $\omega + \delta \ge 0$, the outer rect strictly encloses the border box).*

---

### 2. Core Invariants

1. **Layout Box Isolation Invariant (CSS 2.1 §18.4):**
   * *"Outlines do not take up space."* Computing or applying an outline transformation is a pure ink/visual operation (`VisualOverflowRect`). The layout box's `border_box` dimensions $(x, y, w, h)$ are strictly invariant under any variation of $\omega$ and $\delta$. It triggers neither reflow nor fragmentation shifts.
2. **Visual Bounds Containment Invariant:**
   * Whenever the net expansion is non-negative ($\omega + \delta \ge 0$), the resulting outer outline geometry $O_{ext}$ forms a bounding box that topologically contains the original border box $B$:
   $$[x, x + w] \subseteq [O_x, O_x + O_w] \quad \land \quad [y, y + h] \subseteq [O_y, O_y + O_h]$$
3. **Center-of-Mass / Midpoint Preservation:**
   * Symmetrical expansion by $E$ preserves the geometric center $(2x + w, 2y + h)$ of the box.

---

### 3. Formal Verification: `BlinkOutlineOffsetGeometrySemantics.v`

The following file is a complete, self-contained Rocq/Coq formalization using `ZArith` (matching Blink's fixed-point `LayoutUnit` raw integer representation). It contains **0 admits**.

```coq
(** * BlinkOutlineOffsetGeometrySemantics.v
    Formal Audit by Agent 252: Chromium Blink Outline Geometry vs CSS 2.1 §18.4
    Target: third_party/blink/renderer/core/paint/outline_painter.cc *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Micromega.Lia.

Open Scope Z_scope.

(** ** 1. Geometric Primitives (LayoutUnit Fixed-Point Representation) *)

Record Rect : Type := mkRect {
  rect_x : Z;
  rect_y : Z;
  rect_w : Z;
  rect_h : Z
}.

Definition wf_rect (r : Rect) : Prop :=
  rect_w r >= 0 /\ rect_h r >= 0.

Record OutlineStyle : Type := mkOutlineStyle {
  outline_width  : Z;
  outline_offset : Z
}.

Definition wf_outline_style (s : OutlineStyle) : Prop :=
  outline_width s >= 0.

(** ** 2. Layout State & Visual Ink Overflow Transformation *)

Record BoxState : Type := mkBoxState {
  layout_border_box : Rect;
  visual_outline_box : Rect
}.

(** Blink'sIntRect/PhysicalRect::Inflate(d) semantics *)
Definition inflate_rect (r : Rect) (d : Z) : Rect :=
  mkRect (rect_x r - d)
         (rect_y r - d)
         (rect_w r + 2 * d)
         (rect_h r + 2 * d).

(** Expansion scalar: outline_width + outline_offset *)
Definition outline_expansion (s : OutlineStyle) : Z :=
  outline_width s + outline_offset s.

(** Compute outer outline rect from border box *)
Definition compute_outline_rect (border_box : Rect) (s : OutlineStyle) : Rect :=
  inflate_rect border_box (outline_expansion s).

(** Full state update in Blink Paint/VisualOverflow phase *)
Definition apply_outline_semantics (border_box : Rect) (s : OutlineStyle) : BoxState :=
  mkBoxState border_box (compute_outline_rect border_box s).

(** Bounding box containment predicate: r_inner is within r_outer *)
Definition rect_contains (r_outer r_inner : Rect) : Prop :=
  rect_x r_outer <= rect_x r_inner /\
  rect_y r_outer <= rect_y r_inner /\
  (rect_x r_inner + rect_w r_inner) <= (rect_x r_outer + rect_w r_outer) /\
  (rect_y r_inner + rect_h r_inner) <= (rect_y r_outer + rect_h r_outer).

(** ** 3. Formal Invariants & Theorems (0 Admits) *)

(** Theorem 1 (CSS 2.1 §18.4 Layout Isolation):
    Applying any outline style leaves the layout border box completely unchanged. *)
Theorem blink_outline_layout_box_invariant :
  forall (b : Rect) (s1 s2 : OutlineStyle),
    layout_border_box (apply_outline_semantics b s1) =
    layout_border_box (apply_outline_semantics b s2).
Proof.
  intros b s1 s2.
  unfold apply_outline_semantics; simpl.
  reflexivity.
Qed.

(** Theorem 2 (Well-Formedness Preservation):
    If the border box is well-formed and net expansion is non-negative,
    the resulting visual outline rect is well-formed (non-negative dimensions). *)
Theorem blink_outline_rect_wf :
  forall (b : Rect) (s : OutlineStyle),
    wf_rect b ->
    outline_expansion s >= 0 ->
    wf_rect (compute_outline_rect b s).
Proof.
  intros b s [Hw Hh] Hexp.
  unfold wf_rect, compute_outline_rect, inflate_rect, outline_expansion in *.
  simpl.
  split; lia.
Qed.

(** Theorem 3 (Visual Containment Invariant):
    When outline_width + outline_offset >= 0, the visual outline bounds
    strictly contain the layout border box. *)
Theorem blink_outline_contains_border_box :
  forall (b : Rect) (s : OutlineStyle),
    wf_rect b ->
    outline_expansion s >= 0 ->
    rect_contains (visual_outline_box (apply_outline_semantics b s)) b.
Proof.
  intros b s [Hw Hh] Hexp.
  unfold apply_outline_semantics, compute_outline_rect, inflate_rect, rect_contains.
  simpl.
  repeat split; lia.
Qed.

(** Corollary 3.1 (Standard Non-Negative Offset Containment):
    For any valid CSS outline_width >= 0 and non-negative outline_offset >= 0,
    the visual outline bounds contain the border box. *)
Corollary blink_nonneg_offset_contains_border_box :
  forall (b : Rect) (s : OutlineStyle),
    wf_rect b ->
    wf_outline_style s ->
    outline_offset s >= 0 ->
    rect_contains (compute_outline_rect b s) b.
Proof.
  intros b s Hwf Hstyle Hoffset.
  unfold wf_outline_style in Hstyle.
  apply (blink_outline_contains_border_box b s Hwf).
  unfold outline_expansion.
  lia.
Qed.

(** Theorem 4 (Zero-Expansion Identity):
    If outline_width = 0 and outline_offset = 0 (or they cancel out),
    the visual outline rect is identical to the border box. *)
Theorem blink_outline_zero_expansion_identity :
  forall (b : Rect) (s : OutlineStyle),
    outline_expansion s = 0 ->
    compute_outline_rect b s = b.
Proof.
  intros [x y w h] s Hzero.
  unfold compute_outline_rect, inflate_rect.
  rewrite Hzero.
  simpl.
  f_equal; lia.
Qed.

(** Theorem 5 (Additivity of Inflation / Stepwise Composition):
    Expanding by (width + offset) simultaneously in Blink is algebraically equivalent
    to first offsetting the border box by outline_offset, and then expanding by outline_width. *)
Theorem blink_outline_stepwise_composition :
  forall (b : Rect) (s : OutlineStyle),
    compute_outline_rect b s =
    inflate_rect (inflate_rect b (outline_offset s)) (outline_width s).
Proof.
  intros [x y w h] [ow oo].
  unfold compute_outline_rect, inflate_rect, outline_expansion.
  simpl.
  f_equal; lia.
Qed.

(** Theorem 6 (Homothetic Center Invariance):
    Outline expansion preserves the scaled geometric center (2*x + w, 2*y + h)
    of the border box regardless of width or offset. *)
Theorem blink_outline_preserves_center :
  forall (b : Rect) (s : OutlineStyle),
    let o := compute_outline_rect b s in
    (2 * rect_x o + rect_w o = 2 * rect_x b + rect_w b) /\
    (2 * rect_y o + rect_h o = 2 * rect_y b + rect_h b).
Proof.
  intros [x y w h] s.
  simpl.
  split; lia.
Qed.
```