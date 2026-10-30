### 1. Drop Shadow Rect Union

In Chromium Blink's rendering pipeline (`third_party/blink/renderer/core/svg/svg_fe_drop_shadow_element.cc` and `third_party/blink/renderer/platform/graphics/filters/fe_drop_shadow.cc`), the `<feDropShadow>` filter primitive computes its filter region bounds by combining the input primitive's bounding box with a transformed bounding box representing the blurred and offset shadow.

Given an input bounding rectangle $R_{\text{src}} = (x, y, w, h)$ where $w, h \ge 0$:
1. **Offset Transformation**: The shadow is translated by $(dx, dy)$, shifting the coordinates to $(x + dx, y + dy, w, h)$.
2. **Blur Expansion**: The Gaussian blur kernel expands the rectangle outward on all sides by $k_x = \lceil 3 \sigma_x \rceil$ and $k_y = \lceil 3 \sigma_y \rceil$ (or platform-equivalent directional outset), yielding $R_{\text{blur}} = (x + dx - k_x, y + dy - k_y, w + 2k_x, h + 2k_y)$.
3. **Bounding Box Union**: Because `<feDropShadow>` composites the original source graphic over the blurred shadow, the final output bounding box is the axis-aligned bounding box union:
   $$R_{\text{out}} = \text{union}(R_{\text{src}}, R_{\text{blur}})$$
   The resulting rectangle $R_{\text{out}}$ is defined by taking the minimum of the left/top coordinates and the maximum of the right/bottom coordinates:
   $$x_{\text{out}} = \min(x_{\text{src}}, x_{\text{blur}}), \quad y_{\text{out}} = \min(y_{\text{src}}, y_{\text{blur}})$$
   $$r_{\text{out}} = \max(x_{\text{src}} + w_{\text{src}}, x_{\text{blur}} + w_{\text{blur}}), \quad b_{\text{out}} = \max(y_{\text{src}} + h_{\text{src}}, y_{\text{blur}} + h_{\text{blur}})$$
   $$w_{\text{out}} = r_{\text{out}} - x_{\text{out}}, \quad h_{\text{out}} = b_{\text{out}} - y_{\text{out}}$$

---

### 2. Core Invariants

1. **Containment (`rect_contains`)**: A rectangle $R_1$ is contained within $R_2$ ($R_1 \subseteq R_2$) iff $x_2 \le x_1$, $y_2 \le y_1$, $x_1 + w_1 \le x_2 + w_2$, and $y_1 + h_1 \le y_2 + h_2$. By construction of the extremum operators ($\min$ and $\max$), both $R_{\text{src}} \subseteq \text{union}(R_{\text{src}}, R_{\text{blur}})$ and $R_{\text{blur}} \subseteq \text{union}(R_{\text{src}}, R_{\text{blur}})$ hold unconditionally.
2. **Monotonicity**: If $R_1 \subseteq R_1'$ and $R_2 \subseteq R_2'$, then $\text{union}(R_1, R_2) \subseteq \text{union}(R_1', R_2')$.
3. **Area Non-Shrinking**: For any valid rectangle ($w \ge 0, h \ge 0$), $\text{area}(R) = w \cdot h$. Since $w_{\text{out}} \ge w_{\text{src}} \ge 0$ and $h_{\text{out}} \ge h_{\text{src}} \ge 0$, nonlinear monotonicity of multiplication over non-negative integers guarantees $\text{area}(\text{union}(R_{\text{src}}, R_{\text{blur}})) \ge \text{area}(R_{\text{src}})$.

---

### 3. Rocq / Coq Formalization (`BlinkSVGDropShadowBoundsSemantics.v`)

The following file is completely self-contained and compiles in Rocq / Coq with **0 admits**.

```coq
(** * BlinkSVGDropShadowBoundsSemantics.v
    Formal verification of Chromium Blink feDropShadow bounding box expansion.
    Agent 297 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Psatz.

Open Scope Z_scope.

(** ** 1. Rectangle Representation and Basic Metrics *)

Record Rect : Type := mkRect {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

Definition wf_rect (r : Rect) : Prop :=
  0 <= rw r /\ 0 <= rh r.

Definition r_right (r : Rect) : Z := rx r + rw r.
Definition r_bottom (r : Rect) : Z := ry r + rh r.

Definition rect_area (r : Rect) : Z := rw r * rh r.

(** Geometric containment of bounding intervals: r1 is inside r2 *)
Definition rect_contains (r1 r2 : Rect) : Prop :=
  rx r2 <= rx r1 /\
  ry r2 <= ry r1 /\
  r_right r1 <= r_right r2 /\
  r_bottom r1 <= r_bottom r2.

(** Point-wise containment *)
Definition pt_in_rect (px py : Z) (r : Rect) : Prop :=
  rx r <= px <= r_right r /\
  ry r <= py <= r_bottom r.

(** ** 2. Filter Primitive Operations (Offset, Blur, Union) *)

Definition rect_offset (r : Rect) (dx dy : Z) : Rect :=
  mkRect (rx r + dx) (ry r + dy) (rw r) (rh r).

Definition rect_outset (r : Rect) (kx ky : Z) : Rect :=
  mkRect (rx r - kx) (ry r - ky) (rw r + 2 * kx) (rh r + 2 * ky).

Definition rect_offset_blur (r : Rect) (dx dy kx ky : Z) : Rect :=
  rect_outset (rect_offset r dx dy) kx ky.

Definition rect_union (r1 r2 : Rect) : Rect :=
  let x := Z.min (rx r1) (rx r2) in
  let y := Z.min (ry r1) (ry r2) in
  let right := Z.max (r_right r1) (r_right r2) in
  let bottom := Z.max (r_bottom r1) (r_bottom r2) in
  mkRect x y (right - x) (bottom - y).

Definition fe_drop_shadow_bounds (src : Rect) (dx dy kx ky : Z) : Rect :=
  rect_union src (rect_offset_blur src dx dy kx ky).

(** ** 3. Well-Formedness Proofs *)

Lemma wf_rect_offset : forall r dx dy,
  wf_rect r -> wf_rect (rect_offset r dx dy).
Proof.
  intros r dx dy [Hw Hh].
  unfold wf_rect, rect_offset; simpl.
  split; lia.
Qed.

Lemma wf_rect_outset : forall r kx ky,
  wf_rect r -> 0 <= kx -> 0 <= ky -> wf_rect (rect_outset r kx ky).
Proof.
  intros r kx ky [Hw Hh] Hkx Hky.
  unfold wf_rect, rect_outset; simpl.
  split; lia.
Qed.

Lemma wf_rect_offset_blur : forall r dx dy kx ky,
  wf_rect r -> 0 <= kx -> 0 <= ky -> wf_rect (rect_offset_blur r dx dy kx ky).
Proof.
  intros r dx dy kx ky Hwf Hkx Hky.
  unfold rect_offset_blur.
  apply wf_rect_outset; [apply wf_rect_offset; exact Hwf | exact Hkx | exact Hky].
Qed.

Lemma wf_rect_union : forall r1 r2,
  wf_rect r1 -> wf_rect r2 -> wf_rect (rect_union r1 r2).
Proof.
  intros r1 r2 [Hw1 Hh1] [Hw2 Hh2].
  unfold wf_rect, rect_union, r_right, r_bottom; simpl.
  split; lia.
Qed.

Theorem wf_fe_drop_shadow_bounds : forall src dx dy kx ky,
  wf_rect src -> 0 <= kx -> 0 <= ky ->
  wf_rect (fe_drop_shadow_bounds src dx dy kx ky).
Proof.
  intros src dx dy kx ky Hwf Hkx Hky.
  unfold fe_drop_shadow_bounds.
  apply wf_rect_union.
  - exact Hwf.
  - apply wf_rect_offset_blur; assumption.
Qed.

(** ** 4. Containment Theorems *)

Theorem rect_union_contains_left : forall r1 r2,
  rect_contains r1 (rect_union r1 r2).
Proof.
  intros r1 r2.
  unfold rect_contains, rect_union, r_right, r_bottom; simpl.
  repeat split; lia.
Qed.

Theorem rect_union_contains_right : forall r1 r2,
  rect_contains r2 (rect_union r1 r2).
Proof.
  intros r1 r2.
  unfold rect_contains, rect_union, r_right, r_bottom; simpl.
  repeat split; lia.
Qed.

Theorem fe_drop_shadow_contains_source : forall src dx dy kx ky,
  rect_contains src (fe_drop_shadow_bounds src dx dy kx ky).
Proof.
  intros src dx dy kx ky.
  unfold fe_drop_shadow_bounds.
  apply rect_union_contains_left.
Qed.

Theorem fe_drop_shadow_contains_offset_blur : forall src dx dy kx ky,
  rect_contains (rect_offset_blur src dx dy kx ky) (fe_drop_shadow_bounds src dx dy kx ky).
Proof.
  intros src dx dy kx ky.
  unfold fe_drop_shadow_bounds.
  apply rect_union_contains_right.
Qed.

Theorem rect_contains_pt_monotonic : forall r1 r2 px py,
  rect_contains r1 r2 ->
  pt_in_rect px py r1 ->
  pt_in_rect px py r2.
Proof.
  intros r1 r2 px py [Hx [Hy [Hright Hbottom]]] [Hpx Hpy].
  unfold pt_in_rect in *.
  split; lia.
Qed.

(** ** 5. Monotonicity and Area Invariants *)

Theorem rect_union_monotonic : forall r1 r1' r2 r2',
  rect_contains r1 r1' ->
  rect_contains r2 r2' ->
  rect_contains (rect_union r1 r2) (rect_union r1' r2').
Proof.
  intros r1 r1' r2 r2' [Hx1 [Hy1 [Hr1 Hb1]]] [Hx2 [Hy2 [Hr2 Hb2]]].
  unfold rect_contains, rect_union, r_right, r_bottom in *; simpl.
  repeat split; lia.
Qed.

Lemma rect_contains_dims_le : forall r1 r2,
  rect_contains r1 r2 ->
  rw r1 <= rw r2 /\ rh r1 <= rh r2.
Proof.
  intros r1 r2 [Hx [Hy [Hr Hb]]].
  unfold r_right, r_bottom in *.
  split; lia.
Qed.

Theorem rect_contains_area_monotonic : forall r1 r2,
  wf_rect r1 ->
  rect_contains r1 r2 ->
  rect_area r1 <= rect_area r2.
Proof.
  intros r1 r2 [Hw1 Hh1] Hcont.
  destruct (rect_contains_dims_le r1 r2 Hcont) as [Hrw Hrh].
  unfold rect_area.
  nia.
Qed.

Theorem rect_union_area_ge_left : forall r1 r2,
  wf_rect r1 ->
  rect_area r1 <= rect_area (rect_union r1 r2).
Proof.
  intros r1 r2 Hwf1.
  apply rect_contains_area_monotonic.
  - exact Hwf1.
  - apply rect_union_contains_left.
Qed.

Theorem rect_union_area_ge_right : forall r1 r2,
  wf_rect r2 ->
  rect_area r2 <= rect_area (rect_union r1 r2).
Proof.
  intros r1 r2 Hwf2.
  apply rect_contains_area_monotonic.
  - exact Hwf2.
  - apply rect_union_contains_right.
Qed.

Theorem fe_drop_shadow_area_ge_source : forall src dx dy kx ky,
  wf_rect src ->
  rect_area src <= rect_area (fe_drop_shadow_bounds src dx dy kx ky).
Proof.
  intros src dx dy kx ky Hwf.
  unfold fe_drop_shadow_bounds.
  apply rect_union_area_ge_left.
  exact Hwf.
Qed.

Theorem fe_drop_shadow_area_ge_offset_blur : forall src dx dy kx ky,
  wf_rect src -> 0 <= kx -> 0 <= ky ->
  rect_area (rect_offset_blur src dx dy kx ky) <=
  rect_area (fe_drop_shadow_bounds src dx dy kx ky).
Proof.
  intros src dx dy kx ky Hwf Hkx Hky.
  unfold fe_drop_shadow_bounds.
  apply rect_union_area_ge_right.
  apply wf_rect_offset_blur; assumption.
Qed.
```