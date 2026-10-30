### Audit Report: Chromium Blink Block Height Clamping vs. CSS 2.1 §10.6.4
**Auditor:** Agent 140  
**Target:** Chromium Blink LayoutNG (`ng_length_utils.cc`, `MinMaxSizes::ClampSizeToMinAndMax`) vs. W3C CSS 2.1 §10.7 / §10.6.4  

---

### 1. Clamping Rule Semantics
Under CSS 2.1 §10.7 (*Minimum and maximum heights: 'min-height' and 'max-height'*) and its interaction with §10.6.4, the tentative used height $h$ of a block-level box is constrained by the computed `min-height` ($min\_h$) and `max-height` ($max\_h$) according to a strict three-step conditional evaluation:

1. Calculate tentative height $h$.
2. If $h > max\_h$, re-resolve with $h := max\_h$.
3. If the resulting $h < min\_h$, re-resolve with $h := min\_h$.

Mathematically, this sequential imperative algorithm collapses into the functional clamping expression:
$$\text{resolved\_h}(h, min\_h, max\_h) = \max(min\_h, \min(max\_h, h))$$

In Chromium Blink's LayoutNG engine, this is implemented via `MinMaxSizes::ClampSizeToMinAndMax(LayoutUnit size)`. Blink represents layout dimensions using fixed-point `LayoutUnit` integers (typically $\frac{1}{64}\text{px}$ precision), mapping directly onto total-order integer arithmetic ($\mathbb{Z}$).

---

### 2. The Pathological Case: $min\_h > max\_h$
A critical edge case in layout engines occurs when an author specifies a `min-height` that exceeds `max-height` (e.g., `min-height: 200px; max-height: 100px;`). 

* **CSS 2.1 Specification Mandate:** Step 3 of the §10.7 algorithm states: *"If the resulting height is smaller than 'min-height', the rules above are applied again, but this time using the value of 'min-height' as the computed value for 'height'."* Because the `min-height` check executes *after* the `max-height` check, **`min-height` unconditionally overrides `max-height`**.
* **Algebraic Reduction:** When $min\_h > max\_h$, for any input $h$, we have $\min(max\_h, h) \le max\_h < min\_h$. Therefore:
  $$\max(min\_h, \min(max\_h, h)) = min\_h$$
* **Blink Implementation Audit:** Blink's `MinMaxSizes::ClampSizeToMinAndMax` implements:
  ```cpp
  LayoutUnit ClampSizeToMinAndMax(LayoutUnit size) const {
    return std::max(min_size, std::min(max_size, size));
  }
  ```
  Because `std::max(min_size, ...)` is the outer operation, Blink is strictly conformant with CSS 2.1 §10.7 / §10.6.4.

---

### 3. Core Formal Invariants
To certify Blink's height clamping logic against layout oscillation and out-of-bounds rendering bugs, three algebraic invariants must hold over $\mathbb{Z}$ (`LayoutUnit`):

1. **Absolute Lower Bound (`resolved_h >= min_h`):** Regardless of whether $min\_h \le max\_h$ or $min\_h > max\_h$, the resolved height can never drop below $min\_h$.
2. **Adjusted Upper Bound (`resolved_h <= max(min_h, max_h)`):** Because $min\_h$ can exceed $max\_h$, the naïve invariant $\text{resolved\_h} \le max\_h$ is **false** in CSS. The true universal upper bound is $\max(min\_h, max\_h)$. (When $min\_h \le max\_h$, this simplifies to $\text{resolved\_h} \le max\_h$).
3. **Monotonicity in $h$:** Given fixed constraints $min\_h$ and $max\_h$, if tentative content height grows ($h_1 \le h_2$), the clamped box height must not shrink: $\text{resolved\_h}(h_1) \le \text{resolved\_h}(h_2)$. This guarantees layout stability during incremental intrinsic size passes.

---

### 4. Formal Verification: `BlinkBlockHeightClampingSemantics.v`

Below is the complete, self-contained Rocq (Coq) formalization proving the equivalence of the CSS 2.1 imperative algorithm and Blink's functional expression, along with the three core invariants.

```coq
(** * BlinkBlockHeightClampingSemantics.v
    Formal Audit of Chromium Blink Block Height Clamping vs. CSS 2.1 §10.6.4 / §10.7
    Auditor: Agent 140 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Module BlinkBlockHeightClampingSemantics.

  (** [LayoutUnit] represents Blink's fixed-point layout dimension (1/64th pixel). *)
  Definition LayoutUnit := Z.

  (** ** 1. Definitions *)

  (** Blink's functional clamping implementation:
      `std::max(min_h, std::min(max_h, h))` *)
  Definition clamp_height (min_h max_h h : LayoutUnit) : LayoutUnit :=
    Z.max min_h (Z.min max_h h).

  (** CSS 2.1 §10.7 / §10.6.4 procedural specification:
      Step 1: Start with tentative height h.
      Step 2: If h > max_h, set h := max_h.
      Step 3: If resulting h < min_h, set h := min_h. *)
  Definition css21_spec_resolve_height (min_h max_h h : LayoutUnit) : LayoutUnit :=
    let h_step2 := if Z.gtb h max_h then max_h else h in
    if Z.ltb h_step2 min_h then min_h else h_step2.

  (** Equivalence Theorem: Blink's functional implementation is strictly
      isomorphic to the CSS 2.1 procedural specification for all inputs. *)
  Theorem blink_matches_css21_spec :
    forall (min_h max_h h : LayoutUnit),
      clamp_height min_h max_h h = css21_spec_resolve_height min_h max_h h.
  Proof.
    intros min_h max_h h.
    unfold clamp_height, css21_spec_resolve_height.
    destruct (Z.gtb_spec h max_h); destruct (Z.ltb_spec (if h >? max_h then max_h else h) min_h);
       try lia.
    (* Re-evaluating the inner branch cleanly using Z.ltb_spec *)
    all: unfold Z.gtb in *; destruct (Z.compare h max_h) eqn:Hcmp;
         try discriminate; simpl in *;
         destruct (Z.ltb_spec max_h min_h); try lia;
         destruct (Z.ltb_spec h min_h); lia.
  Qed.

  (** ** 2. Special Case: min_h > max_h *)

  (** CSS 2.1 mandates that when min_h > max_h, min_h wins unconditionally,
      rendering the clamping function constant with respect to h. *)
  Theorem min_wins_over_max :
    forall (min_h max_h h : LayoutUnit),
      min_h > max_h ->
      clamp_height min_h max_h h = min_h.
  Proof.
    intros min_h max_h h H_conflict.
    unfold clamp_height.
    lia.
  Qed.

  (** ** 3. Core Invariants *)

  (** Invariant 3.1: Absolute Lower Bound (resolved_h >= min_h) *)
  Theorem clamp_height_lower_bound :
    forall (min_h max_h h : LayoutUnit),
      clamp_height min_h max_h h >= min_h.
  Proof.
    intros min_h max_h h.
    unfold clamp_height.
    lia.
  Qed.

  (** Invariant 3.2a: Universal Upper Bound (resolved_h <= max(min_h, max_h)) *)
  Theorem clamp_height_universal_upper_bound :
    forall (min_h max_h h : LayoutUnit),
      clamp_height min_h max_h h <= Z.max min_h max_h.
  Proof.
    intros min_h max_h h.
    unfold clamp_height.
    lia.
  Qed.

  (** Invariant 3.2b: Well-Formed Constraint Upper Bound
      When constraints are non-contradictory (min_h <= max_h), resolved_h <= max_h. *)
  Corollary clamp_height_well_formed_upper_bound :
    forall (min_h max_h h : LayoutUnit),
      min_h <= max_h ->
      clamp_height min_h max_h h <= max_h.
  Proof.
    intros min_h max_h h H_wf.
    unfold clamp_height.
    lia.
  Qed.

  (** Invariant 3.3: Monotonicity in Input Height h *)
  Theorem clamp_height_monotonic_in_h :
    forall (min_h max_h h1 h2 : LayoutUnit),
      h1 <= h2 ->
      clamp_height min_h max_h h1 <= clamp_height min_h max_h h2.
  Proof.
    intros min_h max_h h1 h2 H_le.
    unfold clamp_height.
    lia.
  Qed.

  (** Additional Stability Property: Idempotence
      Re-clamping an already clamped height with the same bounds is a no-op. *)
  Theorem clamp_height_idempotent :
    forall (min_h max_h h : LayoutUnit),
      clamp_height min_h max_h (clamp_height min_h max_h h) = clamp_height min_h max_h h.
  Proof.
    intros min_h max_h h.
    unfold clamp_height.
    lia.
  Qed.

End BlinkBlockHeightClampingSemantics.
```