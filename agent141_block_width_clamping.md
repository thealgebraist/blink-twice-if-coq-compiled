### Audit Report: Agent 141
**Target:** Chromium Blink Block Width Clamping (`LayoutUnit` / `MinMaxSizes::ClampSizeToMinAndMax`) vs. CSS 2.1 §10.4 (*Minimum and maximum widths: 'min-width' and 'max-width'*).

---

### 1. Clamping Rule
According to CSS 2.1 §10.4, the tentative used width $w$ is clamped by `min-width` ($\text{min\_w}$) and `max-width` ($\text{max\_w}$) via a three-step procedural rule:
1. Calculate the tentative used width $w$ (without `min-width` and `max-width`).
2. If $w > \text{max\_w}$, the rules are re-applied with $w = \text{max\_w}$.
3. If the resulting width is less than $\text{min\_w}$, the rules are re-applied with $w = \text{min\_w}$.

In Chromium Blink (specifically within `ng_length_utils.cc` and `MinMaxSizes::ClampSizeToMinAndMax`), this procedural sequence is collapsed into the compositional algebraic formula:
$$\text{resolved\_w} = \max(\text{min\_w}, \min(\text{max\_w}, w))$$
Where $\text{max\_w} = \infty$ (represented as `LayoutUnit::Max()`) when `max-width: none` is specified.

---

### 2. Special Case: `min_w > max_w`
When the resolved minimum width exceeds the resolved maximum width ($\text{min\_w} > \text{max\_w}$), CSS 2.1 §10.4 explicitly dictates: 
> *"If 'min-width' is greater than 'max-width', the 'max-width' value is set to the value of 'min-width'."* (i.e., `min-width` wins).

Because Blink applies $\min(\text{max\_w}, w)$ *innermost* and $\max(\text{min\_w}, \dots)$ *outermost*, this conflict resolution is satisfied automatically without branching:
* For any $w$, $\min(\text{max\_w}, w) \le \text{max\_w}$.
* Since $\text{max\_w} < \text{min\_w}$, by transitivity $\min(\text{max\_w}, w) < \text{min\_w}$.
* Therefore, $\max(\text{min\_w}, \min(\text{max\_w}, w))$ strictly evaluates to $\text{min\_w}$.

---

### 3. Semantic Invariants
The Blink clamping implementation upholds three core layout invariants across all integer/fixed-point `LayoutUnit` values ($\mathbb{Z}$):

1. **Lower Bound Preservation:** The resolved width is never smaller than the specified `min-width`:
   $$\forall w, \text{min\_w}, \text{max\_w} \in \mathbb{Z}, \quad \text{resolved\_w} \ge \text{min\_w}$$
2. **Upper Bound Preservation (Conflict-Aware):** The resolved width never exceeds the effective maximum width (which is $\max(\text{min\_w}, \text{max\_w})$):
   $$\forall w, \text{min\_w}, \text{max\_w} \in \mathbb{Z}, \quad \text{resolved\_w} \le \max(\text{min\_w}, \text{max\_w})$$
3. **Monotonicity in Tentative Width:** Clamping is order-preserving with respect to the tentative width $w$:
   $$\forall w_1, w_2, \text{min\_w}, \text{max\_w} \in \mathbb{Z}, \quad w_1 \le w_2 \implies \text{clamp}(w_1) \le \text{clamp}(w_2)$$

---

### 4. Formal Verification (`BlinkBlockWidthClampingSemantics.v`)

Below is the complete, self-contained Rocq/Coq specification and proof script modelling Blink's fixed-point `LayoutUnit` clamping over $\mathbb{Z}$ and verifying its equivalence to CSS 2.1 §10.4.

```coq
(** * BlinkBlockWidthClampingSemantics.v
    Formal Audit by Agent 141: Chromium Blink Block Width Clamping vs CSS 2.1 §10.4 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** [LayoutUnit] in Blink is a 32-bit fixed-point value (6 fractional bits).
    We model its exact arithmetic domain over integers [Z]. *)
Definition LayoutUnit := Z.

(** ** 1. Clamping Definitions *)

(** Blink's compositional clamping formula:
    resolved_w = max(min_w, min(max_w, w)) *)
Definition blink_clamp_width (min_w max_w w : LayoutUnit) : LayoutUnit :=
  Z.max min_w (Z.min max_w w).

(** CSS 2.1 §10.4 procedural specification:
    Step 2: If tentative width > max_w, use max_w.
    Step 3: If resulting width < min_w, use min_w. *)
Definition css21_10_4_clamp_width (min_w max_w w : LayoutUnit) : LayoutUnit :=
  let w_step2 := if Z.gtb w max_w then max_w else w in
  if Z.ltb w_step2 min_w then min_w else w_step2.

(** ** 2. Equivalence & Special Case Theorems *)

(** Theorem: Blink's algebraic clamp is strictly equivalent to CSS 2.1 §10.4's
    procedural two-step conditionals. *)
Theorem blink_matches_css21_10_4 :
  forall min_w max_w w : LayoutUnit,
    blink_clamp_width min_w max_w w = css21_10_4_clamp_width min_w max_w w.
Proof.
  intros min_w max_w w.
  unfold blink_clamp_width, css21_10_4_clamp_width.
  destruct (Z.gtb_spec w max_w) as [Hgt | Hle].
  - (* Case: w > max_w *)
    replace (Z.min max_w w) with max_w by lia.
    destruct (Z.ltb_spec max_w min_w); lia.
  - (* Case: w <= max_w *)
    replace (Z.min max_w w) with w by lia.
    destruct (Z.ltb_spec w min_w); lia.
Qed.

(** Theorem: Special case when min_w > max_w -> min_w strictly wins,
    regardless of the tentative width w. *)
Theorem clamp_min_wins_when_min_gt_max :
  forall min_w max_w w : LayoutUnit,
    min_w > max_w ->
    blink_clamp_width min_w max_w w = min_w.
Proof.
  intros min_w max_w w H_conflict.
  unfold blink_clamp_width.
  lia.
Qed.

(** Corollary: Even when min_w = max_w, the resolved width is constant. *)
Corollary clamp_min_wins_when_min_ge_max :
  forall min_w max_w w : LayoutUnit,
    min_w >= max_w ->
    blink_clamp_width min_w max_w w = min_w.
Proof.
  intros min_w max_w w H_conflict.
  unfold blink_clamp_width.
  lia.
Qed.

(** ** 3. Core Invariants *)

(** Invariant 1: Lower bound is always respected (resolved_w >= min_w). *)
Theorem clamp_lower_bound :
  forall min_w max_w w : LayoutUnit,
    blink_clamp_width min_w max_w w >= min_w.
Proof.
  intros min_w max_w w.
  unfold blink_clamp_width.
  lia.
Qed.

(** Invariant 2: Upper bound is always respected relative to max(min_w, max_w). *)
Theorem clamp_upper_bound :
  forall min_w max_w w : LayoutUnit,
    blink_clamp_width min_w max_w w <= Z.max min_w max_w.
Proof.
  intros min_w max_w w.
  unfold blink_clamp_width.
  lia.
Qed.

(** Invariant 2b: Standard upper bound when constraints are non-conflicting. *)
Theorem clamp_standard_upper_bound :
  forall min_w max_w w : LayoutUnit,
    min_w <= max_w ->
    blink_clamp_width min_w max_w w <= max_w.
Proof.
  intros min_w max_w w H_valid.
  unfold blink_clamp_width.
  lia.
Qed.

(** Invariant 3: Monotonicity with respect to input width w. *)
Theorem clamp_monotonic_in_w :
  forall min_w max_w w1 w2 : LayoutUnit,
    w1 <= w2 ->
    blink_clamp_width min_w max_w w1 <= blink_clamp_width min_w max_w w2.
Proof.
  intros min_w max_w w1 w2 H_le.
  unfold blink_clamp_width.
  lia.
Qed.

(** Invariant 4: Idempotence of clamping. *)
Theorem clamp_idempotent :
  forall min_w max_w w : LayoutUnit,
    blink_clamp_width min_w max_w (blink_clamp_width min_w max_w w) =
    blink_clamp_width min_w max_w w.
Proof.
  intros min_w max_w w.
  unfold blink_clamp_width.
  lia.
Qed.
```