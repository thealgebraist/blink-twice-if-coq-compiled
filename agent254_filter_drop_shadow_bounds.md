### Audit Report: Agent 254 — Chromium Blink Filter Drop-Shadow Bounds vs. CSS Filter Effects 1 §5.4

#### 1. Expansion Mechanics
According to the CSS Filter Effects Module Level 1 (§5.4, `drop-shadow()`), a drop-shadow filter creates an alpha-masked, offset, and blurred copy of the input image, which is then composited beneath the original image (via an `feMerge` of the blurred offset shadow and `SourceGraphic`).

In Chromium Blink (`Source/platform/graphics/filters/FEDropShadow.cpp` and `FilterEffect::MapRect`), the visual paint/cull bounds of an input bounding box $B = (x, y, w, h)$ subjected to a drop-shadow with offset $(dx, dy)$ and blur standard deviation $\sigma$ (represented as an effective pixel expansion radius $\text{blur} = \lceil 3\sigma \rceil \ge 0$) is computed by taking the union of the original box and the expanded, offset shadow box.

For the horizontal axis (and analogously for the vertical axis):
* **Original Interval:** $[x, x + w]$
* **Shadow Interval:** $[x + dx - \text{blur}, x + dx + w + \text{blur}]$
* **Combined Visual Bounds:**
  $$x_{\min} = \min(x, x + dx - \text{blur})$$
  $$x_{\max} = \max(x + w, x + dx + w + \text{blur})$$

---

#### 2. Core Invariants
1. **Original Box Containment:** The resulting visual bounds always fully enclose the original unfiltered geometry $[x, x + w] \times [y, y + h]$, regardless of the offset direction $(dx, dy)$ or blur radius.
2. **Shadow Box Containment:** The resulting visual bounds always fully enclose the offset and blurred shadow geometry $[x + dx - \text{blur}, x + dx + w + \text{blur}] \times [y + dy - \text{blur}, y + dy + h + \text{blur}]$.
3. **Blur Monotonicity:** For any two non-negative blur expansions $b_1 \le b_2$, the visual bounds computed with $b_1$ are strictly contained within the visual bounds computed with $b_2$. Increasing the blur radius never shrinks the visual bounding box along any edge.

---

#### 3. Concrete Rocq / Coq Formalization (`BlinkFilterDropShadowBoundsSemantics.v`)

The following file is self-contained, compiles cleanly with standard Coq/Rocq (`ZArith`, `Lia`), and contains **0 admits**.

```coq
(** * BlinkFilterDropShadowBoundsSemantics.v
    Agent 254 Audit: Chromium Blink Filter Drop-Shadow Bounds vs CSS Filters 1 §5.4
    Formalizes 1D and 2D bounding box expansion, containment invariants,
    and blur radius monotonicity with 0 admits. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1D Interval Representation and Operations *)

Record Interval : Type := mkInterval {
  i_min : Z;
  i_max : Z
}.

(** Well-formedness of an interval: min <= max *)
Definition wf_interval (I : Interval) : Prop :=
  i_min I <= i_max I.

(** Interval containment: I1 is contained within I2 *)
Definition interval_contains (I_outer I_inner : Interval) : Prop :=
  i_min I_outer <= i_min I_inner /\ i_max I_inner <= i_max I_outer.

(** Original 1D span given origin x and size w *)
Definition orig_interval (x w : Z) : Interval :=
  mkInterval x (x + w).

(** Shadow 1D span given origin x, size w, offset d, and blur expansion b *)
Definition shadow_interval (x w d b : Z) : Interval :=
  mkInterval (x + d - b) (x + d + w + b).

(** Combined Drop-Shadow 1D bounds:
    x_min = min(x, x + dx - blur)
    x_max = max(x + w, x + dx + w + blur) *)
Definition drop_shadow_interval (x w d b : Z) : Interval :=
  mkInterval (Z.min x (x + d - b)) (Z.max (x + w) (x + d + w + b)).

(** ** 1D Invariant Proofs *)

Lemma wf_orig_interval : forall x w,
  0 <= w -> wf_interval (orig_interval x w).
Proof.
  intros x w Hw. unfold wf_interval, orig_interval. simpl. lia.
Qed.

Lemma wf_shadow_interval : forall x w d b,
  0 <= w -> 0 <= b -> wf_interval (shadow_interval x w d b).
Proof.
  intros x w d b Hw Hb. unfold wf_interval, shadow_interval. simpl. lia.
Qed.

Theorem wf_drop_shadow_interval : forall x w d b,
  0 <= w -> 0 <= b -> wf_interval (drop_shadow_interval x w d b).
Proof.
  intros x w d b Hw Hb. unfold wf_interval, drop_shadow_interval. simpl. lia.
Qed.

Theorem drop_shadow_interval_contains_orig : forall x w d b,
  interval_contains (drop_shadow_interval x w d b) (orig_interval x w).
Proof.
  intros x w d b.
  unfold interval_contains, drop_shadow_interval, orig_interval. simpl.
  lia.
Qed.

Theorem drop_shadow_interval_contains_shadow : forall x w d b,
  interval_contains (drop_shadow_interval x w d b) (shadow_interval x w d b).
Proof.
  intros x w d b.
  unfold interval_contains, drop_shadow_interval, shadow_interval. simpl.
  lia.
Qed.

Theorem drop_shadow_interval_monotonic_blur : forall x w d b1 b2,
  b1 <= b2 ->
  interval_contains (drop_shadow_interval x w d b2) (drop_shadow_interval x w d b1).
Proof.
  intros x w d b1 b2 Hb.
  unfold interval_contains, drop_shadow_interval. simpl.
  lia.
Qed.

(** ** 2D Bounding Box Representation and Operations *)

Record RectBounds : Type := mkRectBounds {
  x_min : Z;
  x_max : Z;
  y_min : Z;
  y_max : Z
}.

(** Well-formedness of a 2D bounding box *)
Definition wf_rect (R : RectBounds) : Prop :=
  x_min R <= x_max R /\ y_min R <= y_max R.

(** 2D Box containment: R_inner is inside R_outer *)
Definition rect_contains (R_outer R_inner : RectBounds) : Prop :=
  x_min R_outer <= x_min R_inner /\
  x_max R_inner <= x_max R_outer /\
  y_min R_outer <= y_min R_inner /\
  y_max R_inner <= y_max R_outer.

(** Original 2D box from (x, y, w, h) *)
Definition orig_rect (x y w h : Z) : RectBounds :=
  mkRectBounds x (x + w) y (y + h).

(** Shadow 2D box from (x, y, w, h, dx, dy, blur) *)
Definition shadow_rect (x y w h dx dy blur : Z) : RectBounds :=
  mkRectBounds
    (x + dx - blur) (x + dx + w + blur)
    (y + dy - blur) (y + dy + h + blur).

(** Blink Drop-Shadow 2D Visual Bounds *)
Definition drop_shadow_rect (x y w h dx dy blur : Z) : RectBounds :=
  mkRectBounds
    (Z.min x (x + dx - blur))
    (Z.max (x + w) (x + dx + w + blur))
    (Z.min y (y + dy - blur))
    (Z.max (y + h) (y + dy + h + blur)).

(** ** 2D Main Invariant Theorems *)

(** Invariant 0: Well-formed inputs produce well-formed visual bounds. *)
Theorem drop_shadow_rect_wf : forall x y w h dx dy blur,
  0 <= w -> 0 <= h -> 0 <= blur ->
  wf_rect (drop_shadow_rect x y w h dx dy blur).
Proof.
  intros x y w h dx dy blur Hw Hh Hblur.
  unfold wf_rect, drop_shadow_rect. simpl.
  lia.
Qed.

(** Invariant 1a: Visual bounds always contain the original box. *)
Theorem drop_shadow_contains_orig_rect : forall x y w h dx dy blur,
  rect_contains (drop_shadow_rect x y w h dx dy blur) (orig_rect x y w h).
Proof.
  intros x y w h dx dy blur.
  unfold rect_contains, drop_shadow_rect, orig_rect. simpl.
  lia.
Qed.

(** Invariant 1b: Visual bounds always contain the offset blurred shadow box. *)
Theorem drop_shadow_contains_shadow_rect : forall x y w h dx dy blur,
  rect_contains (drop_shadow_rect x y w h dx dy blur) (shadow_rect x y w h dx dy blur).
Proof.
  intros x y w h dx dy blur.
  unfold rect_contains, drop_shadow_rect, shadow_rect. simpl.
  lia.
Qed.

(** Invariant 1c: Visual bounds are the exact tightest bounding box (least upper bound)
    containing both the original box and the shadow box. *)
Theorem drop_shadow_rect_is_least_upper_bound : forall x y w h dx dy blur R,
  rect_contains R (orig_rect x y w h) ->
  rect_contains R (shadow_rect x y w h dx dy blur) ->
  rect_contains R (drop_shadow_rect x y w h dx dy blur).
Proof.
  intros x y w h dx dy blur R Horig Hshad.
  unfold rect_contains, orig_rect, shadow_rect, drop_shadow_rect in *.
  simpl in *.
  lia.
Qed.

(** Invariant 2: Visual bounds are monotonic with respect to the blur radius. *)
Theorem drop_shadow_rect_monotonic_blur : forall x y w h dx dy blur1 blur2,
  blur1 <= blur2 ->
  rect_contains
    (drop_shadow_rect x y w h dx dy blur2)
    (drop_shadow_rect x y w h dx dy blur1).
Proof.
  intros x y w h dx dy blur1 blur2 Hle.
  unfold rect_contains, drop_shadow_rect. simpl.
  lia.
Qed.

(** Identity property: Zero offset and zero blur yields the exact original box. *)
Theorem drop_shadow_zero_identity : forall x y w h,
  drop_shadow_rect x y w h 0 0 0 = orig_rect x y w h.
Proof.
  intros x y w h.
  unfold drop_shadow_rect, orig_rect.
  f_equal; lia.
Qed.
```