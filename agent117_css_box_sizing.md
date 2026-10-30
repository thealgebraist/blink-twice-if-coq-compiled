### Audit Report: Chromium Blink CSS `box-sizing` vs. CSS Box Sizing Module Level 3 §3

**Auditor**: Agent 117  
**Target**: Chromium Blink (`third_party/blink/renderer/core/layout/length_utils.cc` / `computed_style.h`)  
**Specification**: W3C CSS Box Sizing Module Level 3, Section 3 ("Box Sizing: the `box-sizing` property")

---

### 1. Definition of `content-box`
Per CSS Box Sizing 3 §3.1, when `box-sizing: content-box` is specified (the initial value):
* **Content Width ($W_{\text{content}}$)**: The specified `width` (or `height`) $W$ is applied directly to the content box, clamped at $0$ (since negative widths are illegal in CSS and clamped at parse/compute time, though in layout arithmetic we enforce $\max(0, W)$).
* **Border-Box Width ($W_{\text{border}}$)**: The padding and border thicknesses are added outside the content box:
  $$W_{\text{border}} = \max(0, W) + P + B$$
  where $P = \text{padding-left} + \text{padding-right} \ge 0$ and $B = \text{border-left-width} + \text{border-right-width} \ge 0$.

*Blink Alignment*: In `blink::AdjustInlineSizeForBoxSizing`, when `EBoxSizing::kContentBox` is active, Blink takes the resolved length and adds `border_padding.InlineSum()` when computing the border-box size required by the NG layout algorithms (`BoxFragmentBuilder`), or returns the length directly when resolving content size.

---

### 2. Definition of `border-box`
Per CSS Box Sizing 3 §3.1, when `box-sizing: border-box` is specified:
* **Border-Box Width ($W_{\text{border}}$)**: The specified width $W$ dictates the distance between the outer edges of the borders, floored at the sum of padding and border ($P + B$) because the inner content box cannot be negative:
  $$W_{\text{border}} = \max(W, P + B)$$
* **Content Width ($W_{\text{content}}$)**: The content width is obtained by subtracting the padding and border from the specified width, floored at zero:
  $$W_{\text{content}} = \max(0, W - P - B)$$

*Blink Alignment*: In `length_utils.cc`, Blink computes `LayoutUnit::Max(LayoutUnit(), length - border_padding.InlineSum())` when converting a `border-box` specified size to a content size, or `LayoutUnit::Max(border_padding.InlineSum(), length)` when computing the border-box size directly, strictly matching the specification.

---

### 3. Core Invariants
1. **Non-Negativity of Content Width**: For any box-sizing mode $m \in \{\text{content-box}, \text{border-box}\}$, specified width $W \ge 0$, and non-negative edges $P, B \ge 0$:
   $$\text{content\_width}(m, W, P, B) \ge 0$$
2. **Minimum Border-Box Bound**: For any mode, the resulting border-box width is at least the sum of padding and border:
   $$\text{border\_box\_width}(m, W, P, B) \ge P + B$$
3. **Conversion Idempotence**: Normalizing a resolved content width back through `content-box` (or a resolved border-box width back through `border-box`) is an identity operation:
   $$\text{content\_width}(\text{content-box}, \text{content\_width}(m, W, P, B), P, B) = \text{content\_width}(m, W, P, B)$$
   $$\text{border\_box\_width}(\text{border-box}, \text{border\_box\_width}(m, W, P, B), P, B) = \text{border\_box\_width}(m, W, P, B)$$
4. **Invertibility (when $W \ge P + B$)**: Converting a specified width $W \ge P + B$ from `border-box` to content width and then computing its `content-box` border-box width recovers $W$ exactly. Conversely, taking a `content-box` width $W \ge 0$, computing its border-box width, and resolving that under `border-box` recovers $W$:
   $$\forall W \ge P + B,\quad \text{border\_box\_width}(\text{content-box}, \text{content\_width}(\text{border-box}, W, P, B), P, B) = W$$
   $$\forall W \ge 0,\quad \text{content\_width}(\text{border-box}, \text{border\_box\_width}(\text{content-box}, W, P, B), P, B) = W$$

---

### 4. Formal Verification in Rocq/Coq (`BlinkCSSBoxSizingSemantics.v`)

Below is the self-contained, fully proved Rocq/Coq formalization of the CSS Box Sizing semantics and its invariants.

```coq
(** * BlinkCSSBoxSizingSemantics.v
    Formal audit of Chromium Blink CSS box-sizing vs CSS Box Sizing Module Level 3 §3.
    Agent 117 *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Data Types and Definitions *)

Inductive BoxSizing : Type :=
  | ContentBox
  | BorderBox.

(** CSS edge dimensions (padding and border) and specified sizes are modeled over Z
    (representing Blink's fixed-point LayoutUnit). *)

Definition clamp_nonneg (x : Z) : Z :=
  Z.max 0 x.

(** Content width calculation per CSS Box Sizing 3 §3:
    - content-box: max(0, W)
    - border-box:  max(0, W - border - padding) *)
Definition compute_content_width (mode : BoxSizing) (W border padding : Z) : Z :=
  match mode with
  | ContentBox => clamp_nonneg W
  | BorderBox  => clamp_nonneg (W - border - padding)
  end.

(** Border-box width calculation per CSS Box Sizing 3 §3:
    It is always equal to the resolved content width plus border and padding. *)
Definition compute_border_box_width (mode : BoxSizing) (W border padding : Z) : Z :=
  compute_content_width mode W border padding + border + padding.

(** Direct formulation of border-box width used in Blink's NG layout:
    - content-box: max(0, W) + border + padding
    - border-box:  max(W, border + padding) *)
Definition blink_border_box_width (mode : BoxSizing) (W border padding : Z) : Z :=
  match mode with
  | ContentBox => clamp_nonneg W + border + padding
  | BorderBox  => Z.max W (border + padding)
  end.

(** ** 2. Equivalence of Blink's Direct Formulation and Spec Definition *)

Theorem blink_border_box_width_equiv :
  forall (mode : BoxSizing) (W border padding : Z),
    blink_border_box_width mode W border padding =
    compute_border_box_width mode W border padding.
Proof.
  intros mode W border padding.
  unfold blink_border_box_width, compute_border_box_width,
         compute_content_width, clamp_nonneg.
  destruct mode; lia.
Qed.

(** ** 3. Core Invariants *)

(** Invariant 1a: Non-negativity of content width. *)
Theorem content_width_nonneg :
  forall (mode : BoxSizing) (W border padding : Z),
    0 <= compute_content_width mode W border padding.
Proof.
  intros mode W border padding.
  unfold compute_content_width, clamp_nonneg.
  destruct mode; lia.
Qed.

(** Invariant 1b: Border-box width is bounded below by border + padding,
    and is non-negative whenever border and padding are non-negative. *)
Theorem border_box_width_min_bound :
  forall (mode : BoxSizing) (W border padding : Z),
    border + padding <= compute_border_box_width mode W border padding.
Proof.
  intros mode W border padding.
  unfold compute_border_box_width.
  pose proof (content_width_nonneg mode W border padding).
  lia.
Qed.

Theorem border_box_width_nonneg :
  forall (mode : BoxSizing) (W border padding : Z),
    0 <= border ->
    0 <= padding ->
    0 <= compute_border_box_width mode W border padding.
Proof.
  intros mode W border padding Hborder Hpadding.
  pose proof (border_box_width_min_bound mode W border padding).
  lia.
Qed.

(** Invariant 2a: Idempotence of content-width projection under ContentBox. *)
Theorem content_width_idempotent :
  forall (mode : BoxSizing) (W border padding : Z),
    compute_content_width ContentBox
      (compute_content_width mode W border padding) border padding =
    compute_content_width mode W border padding.
Proof.
  intros mode W border padding.
  unfold compute_content_width, clamp_nonneg.
  destruct mode; lia.
Qed.

(** Invariant 2b: Idempotence of border-box-width projection under BorderBox. *)
Theorem border_box_width_idempotent :
  forall (mode : BoxSizing) (W border padding : Z),
    compute_border_box_width BorderBox
      (compute_border_box_width mode W border padding) border padding =
    compute_border_box_width mode W border padding.
Proof.
  intros mode W border padding.
  unfold compute_border_box_width, compute_content_width, clamp_nonneg.
  destruct mode; lia.
Qed.

(** Invariant 2c: Fixed-point property for non-negative W under ContentBox. *)
Theorem content_box_fixed_point :
  forall (W border padding : Z),
    0 <= W ->
    compute_content_width ContentBox W border padding = W.
Proof.
  intros W border padding HW.
  unfold compute_content_width, clamp_nonneg.
  lia.
Qed.

(** Invariant 2d: Fixed-point property for W >= border + padding under BorderBox. *)
Theorem border_box_fixed_point :
  forall (W border padding : Z),
    border + padding <= W ->
    compute_border_box_width BorderBox W border padding = W.
Proof.
  intros W border padding HW.
  unfold compute_border_box_width, compute_content_width, clamp_nonneg.
  lia.
Qed.

(** Invariant 3a: Invertibility from ContentBox to BorderBox (for W >= 0).
    Mapping a non-negative content width W to its border-box width and resolving
    that width as a border-box specification recovers W. *)
Theorem invert_content_to_border :
  forall (W border padding : Z),
    0 <= W ->
    compute_content_width BorderBox
      (compute_border_box_width ContentBox W border padding) border padding = W.
Proof.
  intros W border padding HW.
  unfold compute_border_box_width, compute_content_width, clamp_nonneg.
  lia.
Qed.

(** Invariant 3b: Invertibility from BorderBox to ContentBox (when W >= border + padding).
    Resolving a border-box width W to content width and then computing its
    content-box border-box width recovers W. *)
Theorem invert_border_to_content :
  forall (W border padding : Z),
    border + padding <= W ->
    compute_border_box_width ContentBox
      (compute_content_width BorderBox W border padding) border padding = W.
Proof.
  intros W border padding HW.
  unfold compute_border_box_width, compute_content_width, clamp_nonneg.
  lia.
Qed.

(** Invariant 4: Monotonicity with respect to specified width W. *)
Theorem content_width_monotonic :
  forall (mode : BoxSizing) (W1 W2 border padding : Z),
    W1 <= W2 ->
    compute_content_width mode W1 border padding <=
    compute_content_width mode W2 border padding.
Proof.
  intros mode W1 W2 border padding HW.
  unfold compute_content_width, clamp_nonneg.
  destruct mode; lia.
Qed.
```