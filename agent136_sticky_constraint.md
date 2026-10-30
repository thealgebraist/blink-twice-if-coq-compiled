### 1. Sticky Constraint Rectangle

In Chromium Blink (`StickyPositionScrollingConstraints` in `third_party/blink/renderer/core/page/scrolling/sticky_position_scrolling_constraints.h` and `compositor_sticky_constraints.h`), sticky positioning is resolved by computing a translation offset applied to the element's normal-flow (static) position within its scroll container. This aligns with **CSS Positioned Layout Module Level 3 §6 (Sticky positioning)**.

Let all coordinates be defined in the scroll container's content-box coordinate space along the vertical axis (horizontal is analogous):
* $C_{top}, C_{bottom}$: The top and bottom edges of the containing block's content box, where $C_{height} = C_{bottom} - C_{top} \ge 0$.
* $E_{top}, E_{bottom}$: The static (unshifted) margin-box top and bottom edges of the sticky element, where $E_{height} = E_{bottom} - E_{top} \ge 0$.
* $S_{y}$: The current scroll offset of the scroll container.
* $S_{height}$: The height of the scrollport (the visual viewport of the scroll container).
* $I_{top}, I_{bottom}$: The resolved sticky insets (`top` and `bottom` CSS properties).

#### Constraint Bounds ($min\_offset$ and $max\_offset$)
The sticky element cannot be pulled outside its containing block. Therefore, its translation offset $\Delta y$ is bounded by the available space between its static margin box and its containing block's content box:

1. **Minimum Offset ($min\_y$):** 
   When scrolling up (or via bottom-sticky constraints), the element cannot be pushed above the top edge of its containing block, nor can a top-sticky element be pulled above its own static position:
   $$\text{min\_y} = E_{top}$$
   *(In terms of translation $\Delta y$ relative to static position, $\Delta y_{min} = 0$ for pure top-sticky, or $\min(0, C_{top} - E_{top})$ if bottom-sticky is active).*

2. **Maximum Offset ($max\_y$):**
   When scrolling down, a top-sticky element is pushed down to remain visible, but its bottom margin edge ($E_{bottom} + \Delta y$) cannot exceed the bottom content edge of the containing block ($C_{bottom}$).
   $$\text{max\_y} = \max(E_{top}, C_{bottom} - E_{height})$$
   In terms of relative translation $\Delta y$:
   $$\Delta y_{max} = \max(0, C_{bottom} - E_{bottom})$$

---

### 2. Effective Sticky Offset Clamping

When a `top` inset ($I_{top}$) is specified, the sticky constraint rectangle's top edge at scroll offset $S_y$ is located at:
$$\text{sticky\_view\_top} = S_y + I_{top}$$

To keep the element's shifted top edge ($E'_{top}$) at or below the sticky constraint top edge while respecting its static position and the containing block's bottom boundary, Blink clamps the effective position (and correspondingly the translation offset).

#### Absolute Position Clamping
$$\text{clamped\_y} = \max\big(\text{min\_y}, \min(\text{max\_y}, S_y + I_{top})\big)$$
Expanding $\text{min\_y}$ and $\text{max\_y}$:
$$\text{clamped\_y} = \max\Big(E_{top}, \min\big(\max(E_{top}, C_{bottom} - E_{height}), S_y + I_{top}\big)\Big)$$

#### Relative Translation Offset ($\Delta y$)
In `StickyPositionScrollingConstraints::ComputeStickyOffset`, Blink computes the translation delta $\Delta y = \text{clamped\_y} - E_{top}$:
$$\Delta y = \max\Big(0, \min\big(\max(0, C_{bottom} - E_{bottom}), (S_y + I_{top}) - E_{top}\big)\Big)$$

---

### 3. Invariants

Under the precondition that the sticky element's static box starts at or below the containing block's top edge ($C_{top} \le E_{top}$) and has non-negative height ($E_{height} \ge 0$):

1. **Non-Negative Sticky Translation Bounds (Top-Sticky):**
   A top-sticky constraint can only push the element downward in the layout flow. The translation $\Delta y$ is strictly non-negative, and bounded above by the remaining space in the containing block:
   $$0 \le \Delta y \le \max(0, C_{bottom} - E_{bottom})$$

2. **Containing Block Containment (Lower Bound):**
   The clamped top edge of the sticky element is never placed above its static position or the containing block's top edge:
   $$C_{top} \le E_{top} \le \text{clamped\_y}$$

3. **Containing Block Containment (Upper Bound):**
   If the sticky element fits within the containing block below its static position ($E_{bottom} \le C_{bottom}$), the shifted bottom edge of the sticky element never overflows the containing block's bottom edge:
   $$\text{clamped\_y} + E_{height} \le C_{bottom}$$
   If the sticky element already overflows the containing block statically ($E_{bottom} > C_{bottom}$), $\text{max\_y}$ collapses to $E_{top}$, forcing $\Delta y = 0$ and preventing any further downward overflow:
   $$\text{clamped\_y} + E_{height} \le \max(E_{bottom}, C_{bottom})$$

---

### 4. Concrete Rocq / Coq Formalization (`BlinkStickyConstraintSemantics.v`)

The following self-contained Rocq (Coq) module formalizes the Blink sticky constraint geometry, clamping semantics, and proves the required invariants using `ZArith` and `Lia`.

```coq
(** * BlinkStickyConstraintSemantics.v
    Formalization of Chromium Blink Sticky Positioning Constraints
    vs. CSS Positioned Layout Module Level 3 §6. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Layout Geometry & Constraint Inputs *)

Record StickyConstraintParams := mkStickyParams {
  (* Containing block content-box bounds *)
  cb_top    : Z;
  cb_bottom : Z;

  (* Sticky element static margin-box bounds *)
  elem_top    : Z;
  elem_height : Z;

  (* Scroll state and CSS top inset *)
  scroll_y  : Z;
  top_inset : Z
}.

(** Derived static bottom edge of the sticky element *)
Definition elem_bottom (p : StickyConstraintParams) : Z :=
  elem_top p + elem_height p.

(** Well-formedness conditions for normal-flow geometry *)
Definition wf_sticky_params (p : StickyConstraintParams) : Prop :=
  cb_top p <= cb_bottom p /\
  0 <= elem_height p /\
  cb_top p <= elem_top p.

(** ** 2. Sticky Constraint Rectangle & Clamping Semantics *)

(** Minimum allowed y-coordinate for a top-sticky element *)
Definition min_y (p : StickyConstraintParams) : Z :=
  elem_top p.

(** Maximum allowed y-coordinate before overflowing containing block bottom.
    Note: max(elem_top, cb_bottom - elem_height) ensures min_y <= max_y
    even when the element is larger than the remaining containing block space. *)
Definition max_y (p : StickyConstraintParams) : Z :=
  Z.max (elem_top p) (cb_bottom p - elem_height p).

(** Target position dictated by the scrollport and top inset *)
Definition unshifted_sticky_y (p : StickyConstraintParams) : Z :=
  scroll_y p + top_inset p.

(** Clamped absolute y-coordinate:
    clamped_y = max(min_y, min(max_y, scroll_y + top_inset)) *)
Definition clamped_y (p : StickyConstraintParams) : Z :=
  Z.max (min_y p) (Z.min (max_y p) (unshifted_sticky_y p)).

(** Blink's relative sticky translation offset (Delta y) *)
Definition sticky_translation_y (p : StickyConstraintParams) : Z :=
  clamped_y p - elem_top p.

(** Maximum allowed translation delta *)
Definition max_translation_y (p : StickyConstraintParams) : Z :=
  Z.max 0 (cb_bottom p - elem_bottom p).

(** ** 3. Formal Verification of Invariants *)

(** Lemma: Constraint interval is always valid (min_y <= max_y). *)
Lemma sticky_interval_valid : forall p : StickyConstraintParams,
  min_y p <= max_y p.
Proof.
  intros p.
  unfold min_y, max_y.
  lia.
Qed.

(** Theorem 1: Clamped y is always within [min_y, max_y]. *)
Theorem clamped_y_within_constraint_bounds : forall p : StickyConstraintParams,
  min_y p <= clamped_y p <= max_y p.
Proof.
  intros p.
  unfold clamped_y, min_y, max_y, unshifted_sticky_y.
  lia.
Qed.

(** Theorem 2: Non-negative sticky translation bounds.
    The translation offset is always >= 0 and never exceeds max_translation_y. *)
Theorem sticky_translation_bounds_non_negative : forall p : StickyConstraintParams,
  0 <= sticky_translation_y p <= max_translation_y p.
Proof.
  intros p.
  unfold sticky_translation_y, max_translation_y, clamped_y,
         min_y, max_y, elem_bottom, unshifted_sticky_y.
  lia.
Qed.

(** Theorem 3: Equivalence between absolute clamping and relative offset clamping
    (matches StickyPositionScrollingConstraints::ComputeStickyOffset). *)
Theorem sticky_translation_offset_equivalence : forall p : StickyConstraintParams,
  sticky_translation_y p =
    Z.max 0 (Z.min (max_translation_y p) (unshifted_sticky_y p - elem_top p)).
Proof.
  intros p.
  unfold sticky_translation_y, max_translation_y, clamped_y,
         min_y, max_y, elem_bottom, unshifted_sticky_y.
  lia.
Qed.

(** Theorem 4: Containing Block Containment (Exact Fit Case).
    When the sticky element statically fits within the containing block
    (elem_bottom <= cb_bottom), the shifted element remains strictly inside
    [cb_top, cb_bottom]. *)
Theorem clamped_sticky_within_containing_block : forall p : StickyConstraintParams,
  wf_sticky_params p ->
  elem_bottom p <= cb_bottom p ->
  cb_top p <= clamped_y p /\ clamped_y p + elem_height p <= cb_bottom p.
Proof.
  intros p Hwf Hfit.
  unfold wf_sticky_params in Hwf.
  unfold elem_bottom in Hfit.
  unfold clamped_y, min_y, max_y, unshifted_sticky_y.
  lia.
Qed.

(** Theorem 5: Containing Block Generalized Upper Bound (Overflow Case).
    Even if the sticky element is taller than the containing block,
    sticky positioning never pushes its bottom edge past max(elem_bottom, cb_bottom). *)
Theorem clamped_sticky_generalized_upper_bound : forall p : StickyConstraintParams,
  clamped_y p + elem_height p <= Z.max (elem_bottom p) (cb_bottom p).
Proof.
  intros p.
  unfold clamped_y, min_y, max_y, elem_bottom, unshifted_sticky_y.
  lia.
Qed.

(** Theorem 6: Monotonicity of Sticky Offset with respect to Scroll Offset.
    Scrolling downward (increasing scroll_y) monotonically increases (or keeps equal)
    the clamped sticky position. *)
Theorem clamped_y_monotonic_in_scroll : forall p1 p2 : StickyConstraintParams,
  cb_top p1 = cb_top p2 ->
  cb_bottom p1 = cb_bottom p2 ->
  elem_top p1 = elem_top p2 ->
  elem_height p1 = elem_height p2 ->
  top_inset p1 = top_inset p2 ->
  scroll_y p1 <= scroll_y p2 ->
  clamped_y p1 <= clamped_y p2.
Proof.
  intros p1 p2 Hcbt Hcbb Het Heh Hti Hscroll.
  unfold clamped_y, min_y, max_y, unshifted_sticky_y.
  rewrite Hcbb, Het, Heh, Hti.
  lia.
Qed.
```