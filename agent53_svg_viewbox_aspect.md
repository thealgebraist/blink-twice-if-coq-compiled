### 1. Core Data Structures in Blink SVG Sizing

In Chromium’s Blink engine, SVG coordinate system transformations and viewport fitting are handled primarily inside `third_party/blink/renderer/core/svg/` and `third_party/blink/renderer/core/layout/svg/`.

1. **`LayoutSVGRoot` (`layout_svg_root.h` / `.cc`)**:
   - Inherits from `LayoutReplaced`. It represents the outermost `<svg>` element in the layout tree.
   - Manages the negotiation between CSS layout (intrinsic sizing, replaced element dimensions) and the SVG user coordinate system.
   - Computes `local_to_border_box_transform_` using `SVGSVGElement::ViewBoxToViewTransform`, combining CSS border/padding offsets with the `viewBox` transformation matrix.

2. **`SVGPreserveAspectRatio` (`svg_preserve_aspect_ratio.h` / `.cc`)**:
   - Encapsulates the `preserveAspectRatio` attribute per SVG 2 §7.7.
   - **Alignment Enumeration (`SVGPreserveAspectRatioType`)**:
     - `kSvgPreserveaspectratioUnknown`
     - `kSvgPreserveaspectratioNone`
     - `kSvgPreserveaspectratioXminymin`, `kSvgPreserveaspectratioXmidymin`, `kSvgPreserveaspectratioXmaxymin`
     - `kSvgPreserveaspectratioXminymid`, `kSvgPreserveaspectratioXmidymid` (default), `kSvgPreserveaspectratioXmaxymid`
     - `kSvgPreserveaspectratioXminymax`, `kSvgPreserveaspectratioXmidymax`, `kSvgPreserveaspectratioXmaxymax`
   - **Meet-or-Slice Enumeration (`SVGMeetOrSliceType`)**:
     - `kSvgMeetorsliceUnknown`
     - `kSvgMeetorsliceMeet` (default)
     - `kSvgMeetorsliceSlice`
   - Implements `ComputeTransform(...)`, which produces an `AffineTransform` mapping the `viewBox` rectangle to the target viewport rectangle.

3. **`ViewBoxRect` (`gfx::RectF`)**:
   - Extracted from `SVGFitToViewBox::ViewBox()`.
   - Defined by the tuple $(vb_x, vb_y, vb_w, vb_h) \in \mathbb{R}^4$.
   - Validity constraint enforced by `SVGFitToViewBox::HasValidViewBox()`: $vb_w > 0 \land vb_h > 0$ (note: SVG 2 specifies that negative values are an error and zero values disable rendering of the element, which Blink checks via `IsEmpty()`).

4. **`ViewportRect` (`gfx::RectF` / `gfx::SizeF`)**:
   - The target rendering area in CSS pixels (or parent user units for nested `<svg>`), defined by $(vp_x, vp_y, vp_w, vp_h)$ where $vp_w \ge 0, vp_h \ge 0$. For top-level `<svg>`, $vp_x = 0, vp_y = 0$ relative to the content box.

---

### 2. Scale Factor Computation

Given a valid `ViewBoxRect` $(vb_x, vb_y, vb_w, vb_h)$ with $vb_w > 0, vb_h > 0$ and a `ViewportRect` $(vp_x, vp_y, vp_w, vp_h)$ with $vp_w \ge 0, vp_h \ge 0$:

Let the raw directional scale ratios be:
$$r_x = \frac{vp_w}{vb_w}, \quad r_y = \frac{vp_h}{vb_h}$$

In `SVGPreserveAspectRatio::ComputeTransform`:

1. **Non-Uniform Scaling (`align == kSvgPreserveaspectratioNone`)**:
   - The `meetOrSlice` parameter is ignored.
   - The scale factors are independent:
     $$scale_x = r_x = \frac{vp_w}{vb_w}, \quad scale_y = r_y = \frac{vp_h}{vb_h}$$

2. **Uniform Scaling (`align != kSvgPreserveaspectratioNone`)**:
   - **Meet (`meet_or_slice == kSvgMeetorsliceMeet`)**:
     Preserves aspect ratio such that the entire `viewBox` fits inside the viewport:
     $$scale = \min(r_x, r_y) = \min\left(\frac{vp_w}{vb_w}, \frac{vp_h}{vb_h}\right)$$
     $$scale_x = scale, \quad scale_y = scale$$
   - **Slice (`meet_or_slice == kSvgMeetorsliceSlice`)**:
     Preserves aspect ratio such that the viewport is entirely covered by the `viewBox`:
     $$scale = \max(r_x, r_y) = \max\left(\frac{vp_w}{vb_w}, \frac{vp_h}{vb_h}\right)$$
     $$scale_x = scale, \quad scale_y = scale$$

---

### 3. Alignment Translation Offset

Let the scaled dimensions of the `viewBox` be $W' = vb_w \cdot scale_x$ and $H' = vb_h \cdot scale_y$.
Let the excess (or deficit, if negative under `slice`) viewport dimensions be:
$$\Delta_x = vp_w - W' = vp_w - vb_w \cdot scale_x$$
$$\Delta_y = vp_h - H' = vp_h - vb_h \cdot scale_y$$

When `align == none`, $\Delta_x = 0$ and $\Delta_y = 0$.
The alignment offset $(align_x, align_y)$ within the viewport is computed along each axis independently:

- **X-Axis Alignment**:
  - `xMin*` (`Xminymin`, `Xminymid`, `Xminymax`): $align_x = 0$
  - `xMid*` (`Xmidymin`, `Xmidymid`, `Xmidymax`): $align_x = \frac{\Delta_x}{2} = \frac{vp_w - vb_w \cdot scale_x}{2}$
  - `xMax*` (`Xmaxymin`, `Xmaxymid`, `Xmaxymax`): $align_x = \Delta_x = vp_w - vb_w \cdot scale_x$

- **Y-Axis Alignment**:
  - `*YMin` (`Xminymin`, `Xmidymin`, `Xmaxymin`): $align_y = 0$
  - `*YMid` (`Xminymid`, `Xmidymid`, `Xmaxymid`): $align_y = \frac{\Delta_y}{2} = \frac{vp_h - vb_h \cdot scale_y}{2}$
  - `*YMax` (`Xminymax`, `Xmidymax`, `Xmaxymax`): $align_y = \Delta_y = vp_h - vb_h \cdot scale_y$

#### Total Affine Transformation
A point $(x, y)$ in `viewBox` user space is mapped to viewport space $(x', y')$ by first translating the `viewBox` origin $(-vb_x, -vb_y)$, scaling by $(scale_x, scale_y)$, and translating to the aligned viewport position $(vp_x + align_x, vp_y + align_y)$:
$$x' = vp_x + align_x + scale_x \cdot (x - vb_x)$$
$$y' = vp_y + align_y + scale_y \cdot (y - vb_y)$$

In Blink (`SVGPreserveAspectRatio::ComputeTransform`), this is constructed via matrix operations equivalent to:
$$T_{total} = \text{Translate}(vp_x + align_x, vp_y + align_y) \circ \text{Scale}(scale_x, scale_y) \circ \text{Translate}(-vb_x, -vb_y)$$

---

### 4. Mathematical Invariants

Let the mapped `viewBox` bounding box in viewport coordinates be $[X_0, X_1] \times [Y_0, Y_1]$, where:
$$X_0 = vp_x + align_x, \quad X_1 = vp_x + align_x + vb_w \cdot scale_x$$
$$Y_0 = vp_y + align_y, \quad Y_1 = vp_y + align_y + vb_h \cdot scale_y$$

1. **`meet` Containment Invariant**:
   For `meet`, $scale = \min(vp_w / vb_w, vp_h / vb_h)$.
   Because $vb_w > 0$ and $vb_h > 0$:
   $$W' = vb_w \cdot \min\left(\frac{vp_w}{vb_w}, \frac{vp_h}{vb_h}\right) \le vb_w \cdot \frac{vp_w}{vb_w} = vp_w$$
   $$H' = vb_h \cdot \min\left(\frac{vp_w}{vb_w}, \frac{vp_h}{vb_h}\right) \le vb_h \cdot \frac{vp_h}{vb_h} = vp_h$$
   Consequently, $\Delta_x = vp_w - W' \ge 0$ and $\Delta_y = vp_h - H' \ge 0$.
   For all alignments (`Min`, `Mid`, `Max`), $0 \le align_x \le \Delta_x$ and $0 \le align_y \le \Delta_y$.
   Therefore:
   $$vp_x \le X_0 \le X_1 \le vp_x + vp_w \quad \text{and} \quad vp_y \le Y_0 \le Y_1 \le vp_y + vp_h$$
   The fitted `viewBox` is strictly contained within the `ViewportRect`, and touches at least one pair of opposite edges.

2. **`slice` Coverage Invariant**:
   For `slice`, $scale = \max(vp_w / vb_w, vp_h / vb_h)$.
   Because $vb_w > 0$ and $vb_h > 0$:
   $$W' = vb_w \cdot \max\left(\frac{vp_w}{vb_w}, \frac{vp_h}{vb_h}\right) \ge vb_w \cdot \frac{vp_w}{vb_w} = vp_w$$
   $$H' = vb_h \cdot \max\left(\frac{vp_w}{vb_w}, \frac{vp_h}{vb_h}\right) \ge vb_h \cdot \frac{vp_h}{vb_h} = vp_h$$
   Consequently, $\Delta_x = vp_w - W' \le 0$ and $\Delta_y = vp_h - H' \le 0$.
   For all alignments (`Min`, `Mid`, `Max`), $\Delta_x \le align_x \le 0$ and $\Delta_y \le align_y \le 0$.
   Therefore:
   $$X_0 \le vp_x \le vp_x + vp_w \le X_1 \quad \text{and} \quad Y_0 \le vp_y \le vp_y + vp_h \le Y_1$$
   The scaled `viewBox` completely covers the `ViewportRect`.

3. **Determinism**:
   The computation of $(scale_x, scale_y, tx, ty)$ is a total, pure function over valid rects ($vb_w > 0, vb_h > 0$) and well-formed `SVGPreserveAspectRatio` states.

---

### 5. Rocq / Coq Formalization (`BlinkSVGViewBoxAspectSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the data structures, transformation semantics, and proves the core SVG 2 §7.7 / Blink invariants over the real numbers ($\mathbb{R}$).

```coq
(** * BlinkSVGViewBoxAspectSemantics.v
    Formalization of Chromium Blink SVG viewBox and preserveAspectRatio
    sizing semantics against SVG 2 Section 7.7. *)

From Coq Require Import Reals Lra.
Open Scope R_scope.

(** ** 1. Core Data Structures *)

Inductive AlignAxis : Type :=
  | AlignMin
  | AlignMid
  | AlignMax.

Inductive PreserveAspectRatioAlign : Type :=
  | AlignNone
  | AlignXY (ax ay : AlignAxis).

Inductive MeetOrSlice : Type :=
  | Meet
  | Slice.

Record SVGPreserveAspectRatio : Type := mkPAR {
  par_align : PreserveAspectRatioAlign;
  par_meet_or_slice : MeetOrSlice
}.

(** Standard SVG 2 / Blink alignment presets *)
Definition xMinYMin := AlignXY AlignMin AlignMin.
Definition xMidYMin := AlignXY AlignMid AlignMin.
Definition xMaxYMin := AlignXY AlignMax AlignMin.
Definition xMinYMid := AlignXY AlignMin AlignMid.
Definition xMidYMid := AlignXY AlignMid AlignMid.
Definition xMaxYMid := AlignXY AlignMax AlignMid.
Definition xMinYMax := AlignXY AlignMin AlignMax.
Definition xMidYMax := AlignXY AlignMid AlignMax.
Definition xMaxYMax := AlignXY AlignMax AlignMax.

Record RectF : Type := mkRectF {
  rect_x : R;
  rect_y : R;
  rect_w : R;
  rect_h : R
}.

Definition ValidViewBox (vb : RectF) : Prop :=
  rect_w vb > 0 /\ rect_h vb > 0.

Definition ValidViewport (vp : RectF) : Prop :=
  rect_w vp >= 0 /\ rect_h vp >= 0.

Record ViewBoxTransform : Type := mkTransform {
  scale_x : R;
  scale_y : R;
  trans_x : R;
  trans_y : R
}.

(** ** 2. Scale and Alignment Offset Computation *)

Definition compute_scale (par : SVGPreserveAspectRatio) (vb vp : RectF) : R * R :=
  let rx := rect_w vp / rect_w vb in
  let ry := rect_h vp / rect_h vb in
  match par_align par with
  | AlignNone => (rx, ry)
  | AlignXY _ _ =>
      let s := match par_meet_or_slice par with
               | Meet  => Rmin rx ry
               | Slice => Rmax rx ry
               end in
      (s, s)
  end.

Definition compute_axis_offset (a : AlignAxis) (vp_len vb_len scale : R) : R :=
  let delta := vp_len - vb_len * scale in
  match a with
  | AlignMin => 0
  | AlignMid => delta / 2
  | AlignMax => delta
  end.

Definition compute_viewbox_transform
  (par : SVGPreserveAspectRatio) (vb vp : RectF) : ViewBoxTransform :=
  let (sx, sy) := compute_scale par vb vp in
  let (align_x, align_y) :=
    match par_align par with
    | AlignNone => (0