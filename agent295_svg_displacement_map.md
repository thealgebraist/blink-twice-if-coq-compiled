### 1. Coordinate Displacement Formula Analysis

According to the SVG Filter Effects Specification (and implemented in Chromium Blink's `FEDisplacementMap`), the `feDisplacementMap` filter primitive displaces the pixel values from an input image `in` using the spatial offset encoded in the color channels of a second input image `in2`.

The canonical continuous coordinate mapping formula is defined as:
$$P'(x, y) \leftarrow P\left(x + \text{scale} \cdot \left(XC(x, y) - 0.5\right), \, y + \text{scale} \cdot \left(YC(x, y) - 0.5\right)\right)$$

Where:
* $P'(x, y)$ is the output pixel at coordinate $(x, y)$.
* $P(x', y')$ is the sampled input pixel from `in` at displaced coordinate $(x', y')$.
* $XC(x, y), YC(x, y) \in [0, 1]$ are the normalized color channel values from `in2` designated by `xChannelSelector` and `yChannelSelector`.
* $\text{scale} \in \mathbb{R}$ is the displacement scale factor.

#### Identity Proof for $\text{scale} = 0$:
In Blink's integer/fixed-point rendering pipeline (historically Skia's `SkDisplacementMapEffect`), the normalized channel value $C \in [0, 1]$ is represented as an 8-bit unsigned integer $C_8 \in [0, 255]$, centering the zero-displacement midpoint at $127.5$ (or approximated via $128$ in integer arithmetic):
$$\Delta x = \text{scale} \cdot \left(\frac{XC_8 - 128}{255}\right)$$

When $\text{scale} = 0$:
1. $x' = x + 0 \cdot (XC(x, y) - 0.5) = x + 0 = x$
2. $y' = y + 0 \cdot (YC(x, y) - 0.5) = y + 0 = y$

Thus, $P'(x, y) = P(x, y)$. The transformation strictly degenerates to the identity mapping, independent of the values in `in2`.

---

### 2. Domain Boundedness Invariants

When computing displaced coordinates $(x', y')$, large values of $\text{scale}$ can push the sampling coordinates outside the valid filter primitive subregion (or allocated texture backing store $R = [x_{\min}, x_{\max}] \times [y_{\min}, y_{\max}]$).

To prevent out-of-bounds memory reads in Blink/Skia, coordinate clamping (or border-mode sampling) is enforced prior to pixel lookup:
$$\text{clamp}(v, v_{\min}, v_{\max}) = \max(v_{\min}, \min(v, v_{\max}))$$

#### Invariant:
For any valid bounding rectangle $R$ where $x_{\min} \le x_{\max}$ and $y_{\min} \le y_{\max}$, and for any arbitrary displacement parameters $\text{scale}, XC, YC \in \mathbb{Z}$, the clamped displaced coordinate $(x'_c, y'_c)$ strictly satisfies:
$$(x'_c, y'_c) \in R \iff x_{\min} \le x'_c \le x_{\max} \land y_{\min} \le y'_c \le y_{\max}$$

This guarantees spatial memory safety (no buffer over-reads) regardless of extreme $\text{scale}$ inputs or malformed channel values.

---

### 3. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkSVGDisplacementMapSemantics.v`. It uses integer arithmetic (`Z`) to model discrete pixel coordinates and fixed-point centered channel offsets, with **0 admits**.

```coq
(** 
  File: BlinkSVGDisplacementMapSemantics.v
  Audit: Agent 295 - Chromium Blink feDisplacementMap Coordinate Mapping
  Description: Formal verification of coordinate displacement identity and 
               clamped domain boundedness invariants.
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Micromega.Lia.

Open Scope Z_scope.

(** * 1. Data Structures and Definitions *)

(** Discrete 2D pixel coordinate. *)
Record Point : Type := mkPoint {
  px : Z;
  py : Z
}.

(** Axis-aligned bounding rectangle representing the valid texture domain. *)
Record Rect : Type := mkRect {
  x_min : Z;
  x_max : Z;
  y_min : Z;
  y_max : Z
}.

(** Well-formedness predicate for a bounding rectangle. *)
Definition wf_rect (r : Rect) : Prop :=
  x_min r <= x_max r /\ y_min r <= y_max r.

(** Predicate asserting a Point lies within a Rect. *)
Definition in_rect (p : Point) (r : Rect) : Prop :=
  x_min r <= px p <= x_max r /\ y_min r <= py p <= y_max r.

(** 
  1D coordinate displacement calculation.
  Note: `channel_offset` represents the centered displacement factor 
  (i.e., XC(x,y) - 0.5 in continuous space, or (C - 128) in discrete space).
*)
Definition displace_1d (coord : Z) (scale : Z) (channel_offset : Z) : Z :=
  coord + scale * channel_offset.

(** 2D coordinate displacement mapping. *)
Definition displace_point (p : Point) (scale : Z) (xc_offset yc_offset : Z) : Point :=
  mkPoint (displace_1d (px p) scale xc_offset)
          (displace_1d (py p) scale yc_offset).

(** Clamping function to restrict a value to [low, high]. *)
Definition clamp (val low high : Z) : Z :=
  Z.max low (Z.min val high).

(** 2D clamping to a bounding rectangle. *)
Definition clamp_point (p : Point) (r : Rect) : Point :=
  mkPoint (clamp (px p) (x_min r) (x_max r))
          (clamp (py p) (y_min r) (y_max r)).

(** Safe (clamped) displacement mapping as executed by bounded texture samplers. *)
Definition displace_point_clamped (p : Point) (scale : Z) (xc_offset yc_offset : Z) (r : Rect) : Point :=
  clamp_point (displace_point p scale xc_offset yc_offset) r.


(** * 2. Theorems and Proofs *)

(** Lemma: 1D displacement with scale = 0 is the identity function. *)
Lemma displace_1d_scale_zero : forall (coord channel_offset : Z),
  displace_1d coord 0 channel_offset = coord.
Proof.
  intros coord channel_offset.
  unfold displace_1d.
  lia.
Qed.

(** 
  Theorem 1: Scale = 0 implies P'(x, y) = P(x, y) (Identity Mapping).
  Regardless of the displacement map channel offsets, a scale of 0 leaves 
  the sampling coordinates unchanged.
*)
Theorem displace_point_scale_zero_identity : forall (p : Point) (xc_offset yc_offset : Z),
  displace_point p 0 xc_offset yc_offset = p.
Proof.
  intros [x y] xc_offset yc_offset.
  unfold displace_point.
  simpl.
  rewrite !displace_1d_scale_zero.
  reflexivity.
Qed.

(** Corollary: For any image lookup function P, scale = 0 yields P'(x,y) = P(x,y). *)
Theorem pixel_lookup_scale_zero_identity : 
  forall (Color : Type) (P : Point -> Color) (p : Point) (xc_offset yc_offset : Z),
  P (displace_point p 0 xc_offset yc_offset) = P p.
Proof.
  intros Color P p xc_offset yc_offset.
  rewrite displace_point_scale_zero_identity.
  reflexivity.
Qed.

(** Lemma: 1D clamp preserves bounds when low <= high. *)
Lemma clamp_bounds : forall (val low high : Z),
  low <= high ->
  low <= clamp val low high <= high.
Proof.
  intros val low high H_wf.
  unfold clamp.
  lia.
Qed.

(** 
  Theorem 2: Domain Boundedness Invariant.
  Displacing any point by any scale and channel offsets, when clamped to a 
  well-formed rectangle, strictly preserves domain boundedness.
*)
Theorem displace_point_clamped_in_rect : 
  forall (p : Point) (scale xc_offset yc_offset : Z) (r : Rect),
  wf_rect r ->
  in_rect (displace_point_clamped p scale xc_offset yc_offset r) r.
Proof.
  intros p scale xc_offset yc_offset r H_wf.
  unfold wf_rect in H_wf.
  destruct H_wf as [Hx Hy].
  unfold displace_point_clamped, clamp_point, in_rect.
  simpl.
  split.
  - apply clamp_bounds. exact Hx.
  - apply clamp_bounds. exact Hy.
Qed.

(** 
  Theorem 3: Clamped Identity at Scale = 0 for In-Bounds Points.
  If a point is already within the valid rectangle, clamped displacement 
  with scale = 0 also acts as the exact identity.
*)
Theorem displace_point_clamped_scale_zero_identity :
  forall (p : Point) (xc_offset yc_offset : Z) (r : Rect),
  in_rect p r ->
  displace_point_clamped p 0 xc_offset yc_offset r = p.
Proof.
  intros [x y] xc_offset yc_offset [xmin xmax ymin ymax] H_in.
  unfold in_rect in H_in.
  simpl in H_in.
  destruct H_in as [Hx Hy].
  unfold displace_point_clamped, clamp_point.
  rewrite displace_point_scale_zero_identity.
  simpl.
  unfold clamp.
  f_equal; lia.
Qed.
```