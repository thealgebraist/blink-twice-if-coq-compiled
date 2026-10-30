### 1. Clipping Rect Derivation (`border-box`, `padding-box`, `content-box`)

In Chromium Blink (`third_party/blink/renderer/core/paint/box_painter_base.cc` and `background_image_geometry.cc`), the background painting region is governed by the `background-clip` property as specified in CSS Backgrounds and Borders Module Level 3, §3.7. 

Given a layout box whose outer geometry is anchored at $(X, Y)$ with total dimensions $(W, H)$, let the resolved non-negative box-model edge thicknesses be:
*   **Borders**: $B_t, B_r, B_b, B_l \ge 0$
*   **Paddings**: $P_t, P_r, P_b, P_l \ge 0$

Blink computes the physical clipping rectangles (prior to corner-radius intersection) via progressive inward edge offsets (`PhysicalRect::Contract` / `LayoutRectOutsets`):

1.  **`border-box`**: The background is painted within (and clipped to) the outer perimeter of the border.
    $$\text{Rect}_{\text{border}} = \left( X,\; Y,\; W,\; H \right)$$

2.  **`padding-box`**: The background is clipped to the outer perimeter of the padding edge (inside the border).
    $$\text{Rect}_{\text{padding}} = \left( X + B_l,\; Y + B_t,\; \max(0, W - B_l - B_r),\; \max(0, H - B_t - B_b) \right)$$

3.  **`content-box`**: The background is clipped to the perimeter of the content area (inside both border and padding).
    $$\text{Rect}_{\text{content}} = \left( X + B_l + P_l,\; Y + B_t + P_t,\; \max(0, W - B_l - B_r - P_l - P_r),\; \max(0, H - B_t - B_b - P_t - P_b) \right)$$

*(Note: In formal planar interval arithmetic $[x_{\min}, x_{\max}] \times [y_{\min}, y_{\max}]$, contraction translates directly to inward shifts of the interval bounds: $[x_{\min} + \Delta_l, x_{\max} - \Delta_r]$.)*

---

### 2. Geometric Containment Hierarchy

Per CSS Backgrounds 3 §3.7 and CSS Box Model 3 §2, border widths and padding values are restricted to non-negative real numbers ($\ge 0$). Under Blink’s `LayoutUnit` fixed-point arithmetic (assuming no overflow saturation), inward offsets strictly contract or preserve the bounding intervals:

$$x_{\min}^{\text{border}} \le x_{\min}^{\text{padding}} \le x_{\min}^{\text{content}}$$
$$x_{\max}^{\text{content}} \le x_{\max}^{\text{padding}} \le x_{\max}^{\text{border}}$$
$$y_{\min}^{\text{border}} \le y_{\min}^{\text{padding}} \le y_{\min}^{\text{content}}$$
$$y_{\max}^{\text{content}} \le y_{\max}^{\text{padding}} \le y_{\max}^{\text{border}}$$

This establishes the strict geometric set-inclusion lattice across the three background clip modes:
$$\text{ContentBox} \subseteq \text{PaddingBox} \subseteq \text{BorderBox}$$

---

### 3. Core Invariants

1.  **Non-Negative Edge Validity**: All parsed `border-*-width` and `padding-*` values resolved by `ComputedStyle` satisfy $B_i \ge 0$ and $P_i \ge 0$.
2.  **Clip Area Monotonicity**: Defining the measure $\text{Area}(R) = \max(0, x_{\max} - x_{\min}) \cdot \max(0, y_{\max} - y_{\min})$, the clipping hierarchy guarantees:
    $$0 \le \text{Area}(\text{ContentBox}) \le \text{Area}(\text{PaddingBox}) \le \text{Area}(\text{BorderBox})$$
3.  **Point Containment Transitivity**: For any point $p = (p_x, p_y) \in \mathbb{Z}^2$, if $p$ is visible under a narrower clip mode, it is guaranteed to be visible under all wider clip modes:
    $$p \in \text{ContentBox} \implies p \in \text{PaddingBox} \implies p \in \text{BorderBox}$$
4.  **Idempotence of Degenerate Offsets**: When $B = \mathbf{0}$, $\text{PaddingBox} = \text{BorderBox}$. When $P = \mathbf{0}$, $\text{ContentBox} = \text{PaddingBox}$.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkCSSBackgroundClipSemantics.v`)

The following self-contained Rocq file formalizes Blink's `background-clip` geometry over integer coordinates (`LayoutUnit` abstraction), defines the contraction operators, and proves the containment hierarchy, transitivity, and area monotonicity invariants without axioms.

```coq
(** * BlinkCSSBackgroundClipSemantics.v
    Formal verification of Chromium Blink CSS Background Clipping Geometry
    against CSS Backgrounds and Borders Module Level 3 (Section 3.7).
    Agent 120 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Geometric Primitives and Box Model Types *)

(** Enumeration of CSS background-clip box keywords (CSS Backgrounds 3 §3.7) *)
Inductive BackgroundClipType : Type :=
  | BorderBox
  | PaddingBox
  | ContentBox.

(** Planar point in Blink LayoutUnit space *)
Record Point : Type := mkPoint {
  px : Z;
  py : Z
}.

(** Axis-aligned bounding box represented as closed intervals [xmin, xmax] x [ymin, ymax] *)
Record Rect : Type := mkRect {
  xmin : Z;
   ymin : Z;
  xmax : Z;
  ymax : Z
}.

(** Box-model edge thicknesses (top, right, bottom, left) *)
Record EdgeOutsets : Type := mkOutsets {
  top    : Z;
  right  : Z;
  bottom : Z;
  left   : Z
}.

(** Non-negativity invariant enforced by CSS parsing and Blink ComputedStyle *)
Definition valid_outsets (e : EdgeOutsets) : Prop :=
  e.(top) >= 0 /\ e.(right) >= 0 /\ e.(bottom) >= 0 /\ e.(left) >= 0.

(** Well-formedness of a rectangle (non-inverted bounds) *)
Definition well_formed_rect (r : Rect) : Prop :=
  r.(xmin) <= r.(xmax) /\ r.(ymin) <= r.(ymax).

(** ** 2. Blink Clipping Rect Derivation *)

(** Contracts a rectangle inward by a given set of edge thicknesses *)
Definition contract_rect (r : Rect) (e : EdgeOutsets) : Rect :=
  mkRect (r.(xmin) + e.(left))
         (r.(ymin) + e.(top))
         (r.(xmax) - e.(right))
         (r.(ymax) - e.(bottom)).

(** Derives the target background clip rect for a given clip mode *)
Definition compute_background_clip_rect
  (border_rect : Rect)
  (border : EdgeOutsets)
  (padding : EdgeOutsets)
  (clip : BackgroundClipType) : Rect :=
  match clip with
  | BorderBox  => border_rect
  | PaddingBox => contract_rect border_rect border
  | ContentBox => contract_rect (contract_rect border_rect border) padding
  end.

(** ** 3. Geometric Relations & Measures *)

(** Point-in-rectangle hit / visibility test *)
Definition point_in_rect (p : Point) (r : Rect) : Prop :=
  r.(xmin) <= p.(px) <= r.(xmax) /\
  r.(ymin) <= p.(py) <= r.(ymax).

(** Bounding-box geometric containment (R1 <= R2) *)
Definition rect_le (r1 r2 : Rect) : Prop :=
  r2.(xmin) <= r1.(xmin) /\
  r1.(xmax) <= r2.(xmax) /\
  r2.(ymin) <= r1.(ymin) /\
  r1.(ymax) <= r2.(ymax).

(** Clamped non-negative span and area calculation *)
Definition width (r : Rect) : Z := Z.max 0 (r.(xmax) - r.(xmin)).
Definition height (r : Rect) : Z := Z.max 0 (r.(ymax) - r.(ymin)).
Definition area (r : Rect) : Z := (width r) * (height r).

(** Partial order on BackgroundClipType: ContentBox <= PaddingBox <= BorderBox *)
Definition clip_type_le (c1 c2 : BackgroundClipType) : Prop :=
  match c1, c2 with
  | ContentBox, _          => True
  | PaddingBox, PaddingBox => True
  | PaddingBox, BorderBox  => True
  | BorderBox,  BorderBox  => True
  | _,          _          => False
  end.

(** ** 4. Formal Verification of Invariants and Hierarchy *)

(** Lemma: Contracting a rectangle by valid (non-negative) outsets yields a sub-rectangle *)
Lemma contract_rect_le : forall (r : Rect) (e : EdgeOutsets),
  valid_outsets e ->
  rect_le (contract_rect r e) r.
Proof.
  intros r e [Htop [Hright [Hbottom Hleft]]].
  unfold rect_le, contract_rect; simpl.
  lia.
Qed.

(** Lemma: Reflexivity of rect_le *)
Lemma rect_le_refl : forall (r : Rect),
  rect_le r r.
Proof.
  intros r. unfold rect_le. lia.
Qed.

(** Lemma: Transitivity of rect_le *)
Lemma rect_le_trans : forall (r1 r2 r3 : Rect),
  rect_le r1 r2 -> rect_le r2 r3 -> rect_le r1 r3.
Proof.
  intros r1 r2 r3 H12 H23.
  unfold rect_le in *.
  lia.
Qed.

(** Theorem 1: Geometric Containment Hierarchy
    ContentBox <= PaddingBox <= BorderBox *)
Theorem blink_background_clip_hierarchy :
  forall (base : Rect) (border padding : EdgeOutsets),
    valid_outsets border ->
    valid_outsets padding ->
    let r_border  := compute_background_clip_rect base border padding BorderBox in
    let r_padding := compute_background_clip_rect base border padding PaddingBox in
    let r_content := compute_background_clip_rect base border padding ContentBox in
    rect_le r_content r_padding /\ rect_le r_padding r_border.
Proof.
  intros base border padding Hborder Hpadding r_border r_padding r_content.
  unfold r_border, r_padding, r_content, compute_background_clip_rect.
  split.
  - apply contract_rect_le. exact Hpadding.
  - apply contract_rect_le. exact Hborder.
Qed.

(** Theorem 2: Monotonicity of Clipping Rects with respect to Clip Type Order *)
Theorem clip_type_monotonicity :
  forall (base : Rect) (border padding : EdgeOutsets) (c1 c2 : BackgroundClipType),
    valid_outsets border ->
    valid_outsets padding ->
    clip_type_le c1 c2 ->
    rect_le (compute_background_clip_rect base border padding c1)
            (compute_background_clip_rect base border padding c2).
Proof.
  intros base border padding c1 c2 Hb Hp Hle.
  destruct c1, c2; simpl in Hle; try contradiction;
  unfold compute_background_clip_rect.
  - apply rect_le_refl.
  - apply contract_rect_le; exact Hb.
  - apply rect_le_refl.
  - eapply rect_le_trans.
    + apply contract_rect_le; exact Hp.
    + apply contract_rect_le; exact Hb.
  - apply contract_rect_le; exact Hp.
  - apply rect_le_refl.
Qed.

(** Theorem 3: Point Containment Transitivity Across Clip Modes
    Any pixel painted in a narrower background-clip box is guaranteed to be within
    any wider background-clip box. *)
Theorem point_containment_monotonic :
  forall (p : Point) (r1 r2 : Rect),
    rect_le r1 r2 ->
    point_in_rect p r1 ->
    point_in_rect p r2.
Proof.
  intros p r1 r2 Hle Hpin.
  unfold rect_le in Hle.
  unfold point_in_rect in *.
  lia.
Qed.

Corollary content_to_border_point_inclusion :
  forall (p : Point) (base : Rect) (border padding : EdgeOutsets),
    valid_outsets border ->
    valid_outsets padding ->
    point_in_rect p (compute_background_clip_rect base border padding ContentBox) ->
    point_in_rect p (compute_background_clip_rect base border padding BorderBox).
Proof.
  intros p base border padding Hb Hp Hcontent.
  pose proof (blink_background_clip_hierarchy base border padding Hb Hp) as [Hcp Hpb].
  eapply point_containment_monotonic.
  - eapply rect_le_trans; [exact Hcp | exact Hpb].
  - exact Hcontent.
Qed.

(** Theorem 4: Clip Area Monotonicity Invariant
    Area(ContentBox) <= Area(PaddingBox) <= Area(BorderBox) *)
Lemma rect_le_area_monotonic :
  forall (r1 r2 : Rect),
    rect_le r1 r2 ->
    area r1 <= area r2.
Proof.
  intros r1 r2 Hle.
  unfold rect_le in Hle.
  unfold area, width, height.
  assert (Hw : 0 <= Z.max 0 (xmax r1 - xmin r1) <= Z.max 0 (xmax r2 - xmin r2)) by lia.
  assert (Hh : 0 <= Z.max 0 (ymax r1 - ymin r1) <= Z.max 0 (ymax r2 - ymin r2)) by lia.
  apply Z.mul_le_mono_nonneg; lia.
Qed.

Theorem blink_clip_area_invariant :
  forall (base : Rect) (border padding : EdgeOutsets),
    valid_outsets border ->
    valid_outsets padding ->
    let a_border  := area (compute_background_clip_rect base border padding BorderBox) in
    let a_padding := area (compute_background_clip_rect base border