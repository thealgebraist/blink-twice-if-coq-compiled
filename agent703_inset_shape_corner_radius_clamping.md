# Formal Verification Report: Blink `inset()` Corner Radius Clamping Semantics

**Agent:** 703 (W3C/WHATWG Layout Rules — Grid, Tables, Shapes)  
**Target Theory:** `BlinkInsetShapeCornerRadiusClampingSemantics.v`  
**Chromium Source:** `third_party/blink/renderer/core/layout/shapes/box_shape.cc`  
**Specifications:** CSS Shapes Module Level 1 §3.1 (`inset()`), CSS Backgrounds and Borders Module Level 3 §4.5 (Corner Overlap)

---

## 1. Normative W3C Specification Requirements

The `inset()` function in **CSS Shapes Module Level 1 (§3.1, Supported Shapes)** defines an axis-aligned inset rectangle with optional rounded corners specified via the `<'border-radius'>` syntax:

$$\text{inset()} = \text{inset}( \langle\text{length-percentage}\rangle\{1,4\} \; [\text{round} \; \langle\text{'border-radius'}\rangle] )$$

Normative specification rules for `inset()` corner radii delegate directly to **CSS Backgrounds and Borders Module Level 3 (§4.5, Corner Overlap)**:
> *"Corner curves must not overlap: When the sum of any two adjacent border radii exceeds the size of the border box, UAs must proportionally reduce the used values of all border radii until none of them overlap."*

Specifically, let the inset rectangle have width $W \ge 0$ and height $H \ge 0$. Each corner $c \in \{\text{TL}, \text{TR}, \text{BR}, \text{BL}\}$ has a horizontal radius $r_{c,x} \ge 0$ and a vertical radius $r_{c,y} \ge 0$. The four adjacent corner pairs along the four edges of the inset box are:

1. **Top Edge (Horizontal):** $S_{\text{top}} = r_{\text{TL},x} + r_{\text{TR},x}$ compared against $W$.
2. **Bottom Edge (Horizontal):** $S_{\text{bottom}} = r_{\text{BL},x} + r_{\text{BR},x}$ compared against $W$.
3. **Left Edge (Vertical):** $S_{\text{left}} = r_{\text{TL},y} + r_{\text{BL},y}$ compared against $H$.
4. **Right Edge (Vertical):** $S_{\text{right}} = r_{\text{TR},y} + r_{\text{BR},y}$ compared against $H$.

The normative scaling factor $f$ is defined as:

$$f = \min\left(1, \; \frac{W}{r_{\text{TL},x} + r_{\text{TR},x}}, \; \frac{W}{r_{\text{BL},x} + r_{\text{BR},x}}, \; \frac{H}{r_{\text{TL},y} + r_{\text{BL},y}}, \; \frac{H}{r_{\text{TR},y} + r_{\text{BR},y}}\right)$$

(where terms with zero denominator are ignored). When any edge pair sum $r_1 + r_2 > D$ (for dimension $D \in \{W, H\}$), scaling by $f \le \frac{D}{r_1 + r_2}$ guarantees that the clamped radii $r'_1 = f \cdot r_1$ and $r'_2 = f \cdot r_2$ satisfy:

$$r'_1 + r'_2 \le D \quad \text{and} \quad \forall \text{ symmetric corners } (r_1 = r_2), \quad r'_1 \le \frac{D}{2}$$

---

## 2. Blink Implementation Details & Invariants

In Chromium Blink, `inset()` shapes are represented by `BoxShape` in `third_party/blink/renderer/core/layout/shapes/box_shape.cc`, which wraps a `FloatRoundedRect` (`third_party/blink/renderer/platform/geometry/float_rounded_rect.cc`) constructed by `Shape::CreateInsetShape` in `shape.cc`.

### 2.1 Code Path in `box_shape.cc` and `float_rounded_rect.cc`

In `shape.cc`:
```cpp
scoped_refptr<Shape> Shape::CreateInsetShape(const FloatRoundedRect& bounds) {
  DCHECK_GE(bounds.Rect().Width(), 0);
  DCHECK_GE(bounds.Rect().Height(), 0);
  return base::AdoptRef(new BoxShape(bounds));
}
```

When `BoxShape::ShapeMarginBounds()` or `CreateInsetShape` normalizes the corner radii, it invokes `FloatRoundedRect::ConstrainRadii()`:
```cpp
void FloatRoundedRect::Radii::ScaleAndFloor(float factor) {
  if (factor == 1)
    return;
  // Radii are multiplied by factor and floored/clamped to prevent float overshoot
  top_left_.SetWidth( floor_or_scale(top_left_.Width() * factor) );
  ...
}

void FloatRoundedRect::ConstrainRadii() {
  float factor = 1;
  float horizontal_sum = std::max(radii_.TopLeft().Width() + radii_.TopRight().Width(),
                                  radii_.BottomLeft().Width() + radii_.BottomRight().Width());
  if (horizontal_sum > rect_.Width())
    factor = std::min(factor, rect_.Width() / horizontal_sum);

  float vertical_sum = std::max(radii_.TopLeft().Height() + radii_.BottomLeft().Height(),
                                radii_.TopRight().Height() + radii_.BottomRight().Height());
  if (vertical_sum > rect_.Height())
    factor = std::min(factor, rect_.Height() / vertical_sum);

  DCHECK_LE(factor, 1);
  radii_.Scale(factor);
}
```

### 2.2 Critical Layout Invariants in `box_shape.cc`
`BoxShape::GetExcludedIntervals(LayoutUnit logical_top, LayoutUnit logical_height)` computes line-box exclusions using `FloatRoundedRect::XInterceptsAtY(float y, float& min_x_intercept, float& max_x_intercept)`. `XInterceptsAtY` relies on the following geometric invariants guaranteed by radius clamping:
1. **Non-Negativity Invariant:** All clamped radii $r'_i \ge 0$.
2. **Edge Sum Bound Invariant:** Along any edge of length $w$, $r'_1 + r'_2 \le w$. This ensures the top-left and top-right (or top-left and bottom-left) ellipses never overlap, keeping `CornerRect` regions disjoint along the midpoint of the edge.
3. **Half-Dimension Bound for Uniform Corners:** When $r_1 = r_2 = r$, clamping guarantees $r'_1 \le \lfloor w / 2 \rfloor$, meaning each corner radius never exceeds half the box dimension.
4. **Idempotence Invariant:** Applying `ConstrainRadii()` to an already-constrained `FloatRoundedRect` produces no further reduction (fixed point).

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkInsetShapeCornerRadiusClampingSemantics.v` using `ZArith` (modeling fixed-point `LayoutUnit` / integer subpixel units and scaled rational arithmetic).

```coq
(** * BlinkInsetShapeCornerRadiusClampingSemantics.v
    Formal Verification of CSS Shapes 1 §3.1 inset() Corner Radius Clamping
    in Chromium Blink (third_party/blink/renderer/core/layout/shapes/box_shape.cc) *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Data Types and Geometric Structures *)

(** A pair of adjacent corner radii along a single 1D edge of dimension [w]. *)
Record EdgeRadii := mkEdgeRadii {
  r1 : Z;
  r2 : Z
}.

(** Full 2D Radii of an inset() FloatRoundedRect:
    4 corners, each having horizontal (x) and vertical (y) components. *)
Record BoxRadii := mkBoxRadii {
  tl_x : Z; tl_y : Z;
  tr_x : Z; tr_y : Z;
  bl_x : Z; bl_y : Z;
  br_x : Z; br_y : Z
}.

(** An inset() box geometry with width [w], height [h], and corner radii [radii]. *)
Record InsetBox := mkInsetBox {
  box_w : Z;
  box_h : Z;
  box_radii : BoxRadii
}.

(** ** 2. 1D Edge Clamping Specification
    Mathematical Property:
      scale_factor = if r1 + r2 > w then w / (r1 + r2) else 1
      clamped_r = r * scale_factor
    In integer/fixed-point LayoutUnit arithmetic without floating-point overshoot:
      clamped_r = if r1 + r2 > w then (r * w) / (r1 + r2) else r *)

Definition clamp_radius_1d (r sum w : Z) : Z :=
  if sum >? w then (r * w) / sum else r.

Definition clamp_edge_radii (e : EdgeRadii) (w : Z) : EdgeRadii :=
  let sum := e.(r1) + e.(r2) in
  mkEdgeRadii
    (clamp_radius_1d e.(r1) sum w)
    (clamp_radius_1d e.(r2) sum w).

(** Predicate stating a 1D edge configuration is well-formed (non-negative inputs). *)
Definition wf_edge (e : EdgeRadii) (w : Z) : Prop :=
  0 <= e.(r1) /\ 0 <= e.(r2) /\ 0 <= w.

(** Predicate stating a 1D edge configuration satisfies the CSS Shapes non-overlap invariant. *)
Definition valid_clamped_edge (e : EdgeRadii) (w : Z) : Prop :=
  0 <= e.(r1) /\ 0 <= e.(r2) /\ e.(r1) + e.(r2) <= w.

(** ** 3. 2D Global Box Corner Clamping Specification
    In CSS Shapes 1 / CSS Backgrounds 3 §4.5, all 8 radii are scaled by the
    minimum scale factor across all 4 edges:
      factor = min(1, w / top_sum, w / bottom_sum, h / left_sum, h / right_sum)
    We represent the rational scale factor as a numerator/denominator pair (num, den)
    with 0 <= num <= den and den > 0, and scale any radius r via (r * num) / den. *)

Record ScaleFactor := mkScaleFactor {
  sf_num : Z;
  sf_den : Z
}.

(** Compare two positive-denominator scale factors: f1 <= f2 <-> num1 * den2 <= num2 * den1 *)
Definition sf_le_bool (f1 f2 : ScaleFactor) : bool :=
  (f1.(sf_num) * f2.(sf_den)) <=? (f2.(sf_num) * f1.(sf_den)).

Definition sf_min (f1 f2 : ScaleFactor) : ScaleFactor :=
  if sf_le_bool f1 f2 then f1 else f2.

Definition edge_scale_factor (sum dim : Z) : ScaleFactor :=
  if sum >? dim then mkScaleFactor dim sum else mkScaleFactor 1 1.

Definition compute_box_scale_factor (b : InsetBox) : ScaleFactor :=
  let rad := b.(box_radii) in
  let f_top    := edge_scale_factor (rad.(tl_x) + rad.(tr_x)) b.(box_w) in
  let f_bottom := edge_scale_factor (rad.(bl_x) + rad.(br_x)) b.(box_w) in
  let f_left   := edge_scale_factor (rad.(tl_y) + rad.(bl_y)) b.(box_h) in
  let f_right  := edge_scale_factor (rad.(tr_y) + rad.(br_y)) b.(box_h) in
  sf_min (sf_min f_top f_bottom) (sf_min f_left f_right).

Definition apply_scale (r : Z) (f : ScaleFactor) : Z :=
  (r * f.(sf_num)) / f.(sf_den).

Definition constrain_box_radii (b : InsetBox) : InsetBox :=
  let f := compute_box_scale_factor b in
  let rad := b.(box_radii) in
  mkInsetBox b.(box_w) b.(box_h)
    (mkBoxRadii
      (apply_scale rad.(tl_x) f) (apply_scale rad.(tl_y) f)
      (apply_scale rad.(tr_x) f) (apply_scale rad.(tr_y) f)
      (apply_scale rad.(bl_x) f) (apply_scale rad.(bl_y) f)
      (apply_scale rad.(br_x) f) (apply_scale rad.(br_y) f)).

Definition wf_box (b : InsetBox) : Prop :=
  let rad := b.(box_radii) in
  0 <= b.(box_w) /\ 0 <= b.(box_h) /\
  0 <= rad.(tl_x) /\ 0 <= rad.(tl_y) /\
  0 <= rad.(tr_x) /\ 0 <= rad.(tr_y) /\
  0 <= rad.(bl_x) /\ 0 <= rad.(bl_y) /\
  0 <= rad.(br_x) /\ 0 <= rad.(br_y).
```

---

## 4. Concrete Theorems and Complete Admitted-Free Proofs

We now prove the foundational arithmetic lemmas and main layout theorems using `ZArith` and `Lia`, with zero `Admitted` obligations.

```coq
(** ** 4. Helper Arithmetic Lemmas *)

(** Fundamental lemma: For non-negative integers r1, r2, w and positive s,
    if (r1 + r2) * num <= w * den with den > 0 and num >= 0,
    then (r1 * num) / den + (r2 * num) / den <= w. *)
Lemma div_sum_le_bound : forall r1 r2 num den w : Z,
  0 <= r1 ->
  0 <= r2 ->
  0 <= num ->
  0 < den ->
  (r1 + r2) * num <= w * den ->
  (r1 * num) / den + (r2 * num) / den <= w.
Proof.
  intros r1 r2 num den w Hr1 Hr2 Hnum Hden Hbound.
  pose proof (Z_div_mod_eq_full (r1 * num) den) as Hdiv1.
