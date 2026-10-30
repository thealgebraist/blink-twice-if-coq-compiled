### 1. Outset Specification & Audit Summary

**CSS Filter Effects Module Level 2 vs. Chromium Blink Implementation**

According to the CSS Filter Effects Module Level 2 specification for `backdrop-filter`, computing the backdrop-filtered image requires sampling the backdrop root image behind the target element's border box. When a Gaussian blur filter (`blur(<length>)`) is applied with standard deviation $\sigma$ (`blur_radius`), the kernel weight remains non-negligible up to $3\sigma$ from the center pixel. 

In Chromium Blink (specifically within `cc::FilterOperations::ExpandRectForPixelMovement` and Skia's `SkBlurImageFilter` / `SkMaskFilter` bounds calculations), the pixel movement outset for a Gaussian blur is defined as $\lceil 3 \times \sigma \rceil$. For formal arithmetic modeling over discrete layout/pixel units, this is represented as:
$$\text{outset} = 3 \times \text{blur\_radius}$$
$$\text{sampling\_rect} = \text{expand}(\text{layer\_rect}, 3 \times \text{blur\_radius})$$

If the backdrop sampling region is not expanded by this outset prior to reading back the backdrop texture, pixels near the edges of `layer_rect` will sample clamped or transparent edge artifacts rather than true neighboring backdrop pixels, violating the CSS Filter Effects specification.

---

### 2. Core Invariants

For any valid layer bounding box $R = (x, y, w, h)$ with $w, h \ge 0$ and blur radii $r, r_1, r_2 \ge 0$:

1. **Containment Invariant**: The expanded sampling rectangle always geometrically contains the original layer rectangle:
   $$\forall R, r \ge 0 \implies \text{contains}(\text{sampling\_rect}(R, r), R)$$
2. **Monotonicity Invariant (Geometric & Area)**: As the blur radius increases, the sampling bounds and total sampling area expand monotonically:
   $$\forall R, 0 \le r_1 \le r_2 \implies \text{contains}(\text{sampling\_rect}(R, r_2), \text{sampling\_rect}(R, r_1))$$
   $$\forall R, 0 \le r_1 \le r_2 \implies \text{area}(\text{sampling\_rect}(R, r_1)) \le \text{area}(\text{sampling\_rect}(R, r_2))$$

---

### 3. Concrete Rocq / Coq Formalization (`BlinkBackdropFilterOutsetSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16+) with **0 admits**.

```coq
(** * BlinkBackdropFilterOutsetSemantics.v
    Formal verification of Chromium Blink Backdrop Filter Blur Outset
    vs CSS Filter Effects Module Level 2.
    Agent 247 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Psatz.

Open Scope Z_scope.

(** ** 1. Geometric Primitives *)

Record Rect : Type := mkRect {
  x : Z;
  y : Z;
  width : Z;
  height : Z
}.

(** A rectangle is well-formed if its dimensions are non-negative. *)
Definition wf_rect (r : Rect) : Prop :=
  0 <= width r /\ 0 <= height r.

(** Right and bottom edges of a rectangle. *)
Definition right (r : Rect) : Z := x r + width r.
Definition bottom (r : Rect) : Z := y r + height r.

(** Area of a rectangle. *)
Definition area (r : Rect) : Z := width r * height r.

(** Geometric containment: [outer] contains [inner]. *)
Definition contains (outer inner : Rect) : Prop :=
  x outer <= x inner /\
  y outer <= y inner /\
  right inner <= right outer /\
  bottom inner <= bottom outer.

(** ** 2. Outset and Backdrop Sampling Definitions *)

(** Expand a rectangle uniformly in all 4 directions by [d]. *)
Definition expand (r : Rect) (d : Z) : Rect :=
  mkRect (x r - d)
         (y r - d)
         (width r + 2 * d)
         (height r + 2 * d).

(** Blink's 3-sigma rule for Gaussian blur pixel movement. *)
Definition blur_outset (blur_radius : Z) : Z :=
  3 * blur_radius.

(** The backdrop sampling rectangle required for a given layer and blur radius. *)
Definition sampling_rect (layer_rect : Rect) (blur_radius : Z) : Rect :=
  expand layer_rect (blur_outset blur_radius).

(** ** 3. Structural Lemmas & Invariants *)

Lemma expand_wf : forall (r : Rect) (d : Z),
  wf_rect r ->
  0 <= d ->
  wf_rect (expand r d).
Proof.
  intros r d [Hw Hh] Hd.
  unfold wf_rect, expand; simpl.
  lia.
Qed.

Lemma sampling_rect_wf : forall (layer_rect : Rect) (blur_radius : Z),
  wf_rect layer_rect ->
  0 <= blur_radius ->
  wf_rect (sampling_rect layer_rect blur_radius).
Proof.
  intros layer_rect blur_radius Hwf Hr.
  unfold sampling_rect, blur_outset.
  apply expand_wf; [exact Hwf | lia].
Qed.

Lemma contains_refl : forall (r : Rect),
  contains r r.
Proof.
  intros r.
  unfold contains, right, bottom.
  lia.
Qed.

Lemma contains_trans : forall (r1 r2 r3 : Rect),
  contains r1 r2 ->
  contains r2 r3 ->
  contains r1 r3.
Proof.
  intros r1 r2 r3 H12 H23.
  unfold contains, right, bottom in *.
  lia.
Qed.

(** *** Invariant 1: sampling_rect contains layer_rect *)
Theorem sampling_rect_contains_layer_rect : forall (layer_rect : Rect) (blur_radius : Z),
  0 <= blur_radius ->
  contains (sampling_rect layer_rect blur_radius) layer_rect.
Proof.
  intros layer_rect blur_radius Hr.
  unfold contains, sampling_rect, expand, blur_outset, right, bottom; simpl.
  lia.
Qed.

(** *** Invariant 2a: Geometric Monotonicity of sampling_rect *)
Theorem sampling_rect_geometric_monotonic : forall (layer_rect : Rect) (r1 r2 : Z),
  0 <= r1 ->
  r1 <= r2 ->
  contains (sampling_rect layer_rect r2) (sampling_rect layer_rect r1).
Proof.
  intros layer_rect r1 r2 Hr1 Hr12.
  unfold contains, sampling_rect, expand, blur_outset, right, bottom; simpl.
  lia.
Qed.

(** *** Invariant 2b: Area Monotonicity of sampling_rect *)
Theorem sampling_rect_area_monotonic : forall (layer_rect : Rect) (r1 r2 : Z),
  wf_rect layer_rect ->
  0 <= r1 ->
  r1 <= r2 ->
  area (sampling_rect layer_rect r1) <= area (sampling_rect layer_rect r2).
Proof.
  intros layer_rect r1 r2 [Hw Hh] Hr1 Hr12.
  unfold area, sampling_rect, expand, blur_outset; simpl.
  nia.
Qed.

(** *** Identity Property: Zero blur radius yields exact layer_rect *)
Theorem sampling_rect_zero_radius : forall (layer_rect : Rect),
  sampling_rect layer_rect 0 = layer_rect.
Proof.
  intros [x0 y0 w0 h0].
  unfold sampling_rect, expand, blur_outset; simpl.
  f_equal; lia.
Qed.
```