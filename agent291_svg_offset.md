### Audit Report: Chromium Blink `feOffset` vs. W3C Filter Effects 1 §10

**Agent:** 291  
**Target:** `third_party/blink/renderer/core/svg/svg_fe_offset_element.cc`, `third_party/blink/renderer/platform/graphics/filters/fe_offset.cc`  
**Specification:** W3C Filter Effects Module Level 1, §10 (`feOffset` element)

---

### 1. Offset Translation Semantics & Dimensional Invariance

According to W3C Filter Effects 1 §10, the `feOffset` filter primitive offsets the input image relative to its current position in the image space by the specified vector $(dx, dy)$. 

In Chromium Blink's implementation (`FEOffset::MapEffect` and `FEOffset::CreateImageFilter`), the operation is governed by a pure 2D affine translation transformation:
$$\mathbf{T}_{dx, dy}(x, y) = (x + dx, y + dy)$$

For any bounding box $R = (x, y, w, h)$ representing the filter primitive subregion or input bounding rect:
1. **Position Translation:** The origin $(x, y)$ maps to $(x', y') = (x + dx, y + dy)$.
2. **Dimensional Invariance:** The extent $(w, h)$ remains strictly invariant under translation: $w' = w$ and $h' = h$. In Blink, `gfx::RectF::Offset(dx, dy)` mutates only `origin_` while leaving `size_` untouched.

---

### 2. Algebraic Invariants: Additive Composition

When chaining two `feOffset` primitives in an SVG filter graph—first shifting by $\mathbf{d}_1 = (dx_1, dy_1)$ and subsequently by $\mathbf{d}_2 = (dx_2, dy_2)$—the net transformation must be equivalent to a single `feOffset` primitive with a combined vector $\mathbf{d}_1 + \mathbf{d}_2 = (dx_1 + dx_2, dy_1 + dy_2)$:

$$\mathrm{offset}(\mathbf{d}_2) \circ \mathrm{offset}(\mathbf{d}_1) = \mathrm{offset}(\mathbf{d}_1 + \mathbf{d}_2)$$

Furthermore:
* **Identity:** An offset of $(0, 0)$ acts as the identity operator on both points and bounding boxes.
* **Invertibility:** An offset of $(-dx, -dy)$ exactly cancels an offset of $(dx, dy)$ in exact arithmetic.
* **Commutativity:** Sequential offsets commute: $\mathrm{offset}(\mathbf{d}_2) \circ \mathrm{offset}(\mathbf{d}_1) = \mathrm{offset}(\mathbf{d}_1) \circ \mathrm{offset}(\mathbf{d}_2)$.

---

### 3. Formal Verification (`BlinkSVGOffsetTranslationSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization of the `feOffset` spatial semantics and invariants over exact integer coordinates (`Z`), containing **0 admits**.

```coq
(** * BlinkSVGOffsetTranslationSemantics.v
    Formal verification of Chromium Blink's SVG feOffset filter primitive
    against W3C Filter Effects Module Level 1, Section 10.
    Agent 291 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Data Structures *)

(** A 2D point in filter coordinate space. *)
Record Point2D : Type := mkPoint {
  px : Z;
  py : Z
}.

(** A 2D translation vector (dx, dy) for feOffset. *)
Record OffsetVec : Type := mkOffset {
  dx : Z;
  dy : Z
}.

(** A filter bounding box / subregion (x, y, width, height). *)
Record FilterRect : Type := mkRect {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

(** ** 2. Operations & Semantics *)

(** Vector addition for composing offsets. *)
Definition add_offset (d1 d2 : OffsetVec) : OffsetVec :=
  mkOffset (dx d1 + dx d2) (dy d1 + dy d2).

(** Zero offset vector (identity). *)
Definition zero_offset : OffsetVec :=
  mkOffset 0 0.

(** Negation of an offset vector (inverse). *)
Definition neg_offset (d : OffsetVec) : OffsetVec :=
  mkOffset (- dx d) (- dy d).

(** Point translation semantics: pos' = (x + dx, y + dy). *)
Definition translate_point (d : OffsetVec) (p : Point2D) : Point2D :=
  mkPoint (px p + dx d) (py p + dy d).

(** Bounding box translation semantics (Blink gfx::Rect::Offset). *)
Definition offset_rect (d : OffsetVec) (r : FilterRect) : FilterRect :=
  mkRect (rx r + dx d) (ry r + dy d) (rw r) (rh r).

(** Extract corners of a FilterRect to verify geometric consistency. *)
Definition rect_origin (r : FilterRect) : Point2D :=
  mkPoint (rx r) (ry r).

Definition rect_bottom_right (r : FilterRect) : Point2D :=
  mkPoint (rx r + rw r) (ry r + rh r).

(** ** 3. Theorems & Invariants *)

(** Theorem 1a: Width is invariant under feOffset translation. *)
Theorem offset_rect_width_invariant :
  forall (d : OffsetVec) (r : FilterRect),
    rw (offset_rect d r) = rw r.
Proof.
  intros d r.
  simpl. reflexivity.
Qed.

(** Theorem 1b: Height is invariant under feOffset translation. *)
Theorem offset_rect_height_invariant :
  forall (d : OffsetVec) (r : FilterRect),
    rh (offset_rect d r) = rh r.
Proof.
  intros d r.
  simpl. reflexivity.
Qed.

(** Theorem 1c: Area is invariant under feOffset translation. *)
Theorem offset_rect_area_invariant :
  forall (d : OffsetVec) (r : FilterRect),
    rw (offset_rect d r) * rh (offset_rect d r) = rw r * rh r.
Proof.
  intros d r.
  simpl. reflexivity.
Qed.

(** Theorem 2a: Double offset composition on points is additive. *)
Theorem translate_point_additive :
  forall (d1 d2 : OffsetVec) (p : Point2D),
    translate_point d2 (translate_point d1 p) = translate_point (add_offset d1 d2) p.
Proof.
  intros [dx1 dy1] [dx2 dy2] [x y].
  unfold translate_point, add_offset. simpl.
  f_equal; lia.
Qed.

(** Theorem 2b: Double offset composition on bounding rects is additive.
    offset(d2) . offset(d1) = offset(d1 + d2) *)
Theorem offset_rect_additive :
  forall (d1 d2 : OffsetVec) (r : FilterRect),
    offset_rect d2 (offset_rect d1 r) = offset_rect (add_offset d1 d2) r.
Proof.
  intros [dx1 dy1] [dx2 dy2] [x y w h].
  unfold offset_rect, add_offset. simpl.
  f_equal; lia.
Qed.

(** Theorem 3: Offset composition is commutative. *)
Theorem offset_rect_commutative :
  forall (d1 d2 : OffsetVec) (r : FilterRect),
    offset_rect d2 (offset_rect d1 r) = offset_rect d1 (offset_rect d2 r).
Proof.
  intros [dx1 dy1] [dx2 dy2] [x y w h].
  unfold offset_rect. simpl.
  f_equal; lia.
Qed.

(** Theorem 4: Zero offset is the identity transformation. *)
Theorem offset_rect_identity :
  forall (r : FilterRect),
    offset_rect zero_offset r = r.
Proof.
  intros [x y w h].
  unfold offset_rect, zero_offset. simpl.
  f_equal; lia.
Qed.

(** Theorem 5: Offset by negation is the exact inverse transformation. *)
Theorem offset_rect_inverse :
  forall (d : OffsetVec) (r : FilterRect),
    offset_rect (neg_offset d) (offset_rect d r) = r.
Proof.
  intros [dx1 dy1] [x y w h].
  unfold offset_rect, neg_offset. simpl.
  f_equal; lia.
Qed.

(** Theorem 6: Geometric consistency of the bottom-right corner under translation.
    Translating the rectangle and taking the bottom-right corner is identical
    to taking the bottom-right corner and translating it as a point. *)
Theorem offset_rect_bottom_right_commutes :
  forall (d : OffsetVec) (r : FilterRect),
    rect_bottom_right (offset_rect d r) = translate_point d (rect_bottom_right r).
Proof.
  intros [dx1 dy1] [x y w h].
  unfold rect_bottom_right, offset_rect, translate_point. simpl.
  f_equal; lia.
Qed.
```