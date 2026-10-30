### Audit Report: Agent 234 — Chromium Blink `fit-content` Formula vs. CSS Sizing 3 §4

---

### 1. Specification & Implementation Analysis

#### 1.1 CSS Box Sizing Module Level 3 (§4.1 / §5.1)
According to the W3C CSS Box Sizing Module Level 3 specification, the `fit-content` size (and `fit-content(<length-percentage>)`) resolves by clamping the available space between the minimum content contribution and the maximum content contribution:
$$\text{fit-content}(\text{min\_c}, \text{max\_c}, \text{avail}) = \max(\text{min\_c}, \min(\text{max\_c}, \text{avail}))$$

Note that CSS Sizing 3 explicitly orders the resolution such that the `max` operation dominates the `min` operation. Therefore, if a degenerate layout state produces $\text{min\_c} > \text{max\_c}$, the resolved size is guaranteed to be at least $\text{min\_c}$.

#### 1.2 Chromium Blink Implementation
In Chromium’s Blink LayoutNG engine (`third_party/blink/renderer/core/layout/length_utils.h` and `min_max_sizes.h`), intrinsic size clamping is implemented on the `MinMaxSizes` struct:

```cpp
LayoutUnit MinMaxSizes::ClampSizeToMinAndMax(LayoutUnit size) const {
  return std::max(min_size, std::min(max_size, size));
}
```

When resolving `fit-content(avail)`, Blink invokes `sizes.ClampSizeToMinAndMax(available_size)`. This directly mirrors the specification:
$$\text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}) = \max(\text{min\_c}, \min(\text{max\_c}, \text{avail}))$$

---

### 2. Core Invariants

Assuming exact arithmetic over $\mathbb{Z}$ (representing fixed-point `LayoutUnit` raw values prior to saturation limits):

1. **Lower Bound Dominance (Unconditional):**
   $$\forall \text{min\_c}, \text{max\_c}, \text{avail} \in \mathbb{Z}, \quad \text{min\_c} \le \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail})$$
2. **Well-Formedness Bounding ($\text{min\_c} \le \text{max\_c}$):**
   $$\text{min\_c} \le \text{max\_c} \implies \text{min\_c} \le \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}) \le \text{max\_c}$$
3. **In-Range Identity:**
   $$\text{min\_c} \le \text{avail} \le \text{max\_c} \implies \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}) = \text{avail}$$
4. **Underflow Clamping:**
   $$\text{avail} \le \text{min\_c} \implies \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}) = \text{min\_c}$$
5. **Overflow Clamping (under well-formedness):**
   $$\text{min\_c} \le \text{max\_c} \land \text{max\_c} \le \text{avail} \implies \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}) = \text{max\_c}$$
6. **Monotonicity in Available Space:**
   $$\text{avail}_1 \le \text{avail}_2 \implies \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}_1) \le \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail}_2)$$
7. **Idempotence:**
   $$\text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail})) = \text{fit\_content}(\text{min\_c}, \text{max\_c}, \text{avail})$$

---

### 3. Formal Verification in Rocq/Coq (`BlinkFitContentClampSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16–8.20+) with **0 admits**.

```coq
(** * BlinkFitContentClampSemantics.v
    Audit Agent 234: Chromium Blink Fit-Content Formula vs CSS Sizing 3 §4.
    Formal verification of intrinsic size clamping semantics. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section FitContentSemantics.

  (** [LayoutUnit] is modeled as an arbitrary-precision integer representing
      the underlying fixed-point ticks (1/64th of a pixel in Blink). *)
  Definition LayoutUnit := Z.

  (** CSS Sizing 3 §4.1 & Blink [MinMaxSizes::ClampSizeToMinAndMax]:
      fit-content(min_c, max_c, avail) = max(min_c, min(max_c, avail)) *)
  Definition fit_content (min_c max_c avail : LayoutUnit) : LayoutUnit :=
    Z.max min_c (Z.min max_c avail).

  (** Alternative formulation where min dominates max. *)
  Definition clamp_min_dominates (min_c max_c avail : LayoutUnit) : LayoutUnit :=
    Z.min max_c (Z.max min_c avail).

  (** Theorem 1: Unconditional Lower Bound.
      Even if min_c > max_c (degenerate intrinsic sizes), min_c dominates. *)
  Theorem fit_content_lower_bound_unconditional :
    forall min_c max_c avail : LayoutUnit,
      min_c <= fit_content min_c max_c avail.
  Proof.
    intros min_c max_c avail.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 2: Primary Bounding Invariant.
      When min_c <= max_c, fit_content is strictly bounded within [min_c, max_c]. *)
  Theorem fit_content_bounds :
    forall min_c max_c avail : LayoutUnit,
      min_c <= max_c ->
      min_c <= fit_content min_c max_c avail <= max_c.
  Proof.
    intros min_c max_c avail Hwf.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 3: Exact Identity within Range.
      When min_c <= avail <= max_c, fit_content resolves to avail. *)
  Theorem fit_content_in_range_identity :
    forall min_c max_c avail : LayoutUnit,
      min_c <= avail <= max_c ->
      fit_content min_c max_c avail = avail.
  Proof.
    intros min_c max_c avail Hrange.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 4: Underflow Clamping.
      When avail <= min_c, fit_content resolves to min_c regardless of max_c. *)
  Theorem fit_content_underflow :
    forall min_c max_c avail : LayoutUnit,
      avail <= min_c ->
      fit_content min_c max_c avail = min_c.
  Proof.
    intros min_c max_c avail Hunder.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 5: Overflow Clamping.
      When min_c <= max_c and max_c <= avail, fit_content resolves to max_c. *)
  Theorem fit_content_overflow :
    forall min_c max_c avail : LayoutUnit,
      min_c <= max_c ->
      max_c <= avail ->
      fit_content min_c max_c avail = max_c.
  Proof.
    intros min_c max_c avail Hwf Hover.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 6: Degenerate Interval Resolution (min_c > max_c).
      CSS Sizing 3 specifies max(min_c, min(max_c, avail)), so min_c wins. *)
  Theorem fit_content_degenerate_min_wins :
    forall min_c max_c avail : LayoutUnit,
      max_c <= min_c ->
      fit_content min_c max_c avail = min_c.
  Proof.
    intros min_c max_c avail Hdeg.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 7: Equivalence of Clamp Orderings under Well-Formedness.
      max(min_c, min(max_c, avail)) = min(max_c, max(min_c, avail)) iff min_c <= max_c. *)
  Theorem fit_content_clamp_commutes_iff_wf :
    forall min_c max_c : LayoutUnit,
      (forall avail : LayoutUnit,
         fit_content min_c max_c avail = clamp_min_dominates min_c max_c avail) <->
      min_c <= max_c.
  Proof.
    intros min_c max_c.
    unfold fit_content, clamp_min_dominates.
    split.
    - intros H.
      specialize (H min_c).
      lia.
    - intros Hwf avail.
      lia.
  Qed.

  (** Theorem 8: Monotonicity with respect to Available Space. *)
  Theorem fit_content_monotone_avail :
    forall min_c max_c avail1 avail2 : LayoutUnit,
      avail1 <= avail2 ->
      fit_content min_c max_c avail1 <= fit_content min_c max_c avail2.
  Proof.
    intros min_c max_c avail1 avail2 Hle.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 9: Monotonicity with respect to Min-Content. *)
  Theorem fit_content_monotone_min_c :
    forall min_c1 min_c2 max_c avail : LayoutUnit,
      min_c1 <= min_c2 ->
      fit_content min_c1 max_c avail <= fit_content min_c2 max_c avail.
  Proof.
    intros min_c1 min_c2 max_c avail Hle.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 10: Monotonicity with respect to Max-Content. *)
  Theorem fit_content_monotone_max_c :
    forall min_c max_c1 max_c2 avail : LayoutUnit,
      max_c1 <= max_c2 ->
      fit_content min_c max_c1 avail <= fit_content min_c max_c2 avail.
  Proof.
    intros min_c max_c1 max_c2 avail Hle.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 11: Idempotence of Clamping.
      Re-clamping an already resolved fit-content size is a no-op. *)
  Theorem fit_content_idempotent :
    forall min_c max_c avail : LayoutUnit,
      fit_content min_c max_c (fit_content min_c max_c avail) =
      fit_content min_c max_c avail.
  Proof.
    intros min_c max_c avail.
    unfold fit_content.
    lia.
  Qed.

  (** Theorem 12: Non-negativity Preservation.
      If min_c >= 0, fit_content is guaranteed non-negative even if avail < 0. *)
  Theorem fit_content_nonneg :
    forall min_c max_c avail : LayoutUnit,
      0 <= min_c ->
      0 <= fit_content min_c max_c avail.
  Proof.
    intros min_c max_c avail Hnonneg.
    unfold fit_content.
    lia.
  Qed.

End FitContentSemantics.
```