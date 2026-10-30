### Audit Report: Agent 235
**Target**: Chromium Blink Layout Engine (Constraint Space / Sizing Resolution)
**Specification**: CSS 2.1 §10.4 (*Minimum and maximum widths: 'min-width' and 'max-width'*)

---

### 1. Formula Resolution
According to CSS 2.1 §10.4, the tentative used width (`target`) is resolved against `min-width` (`min_w`) and `max-width` (`max_w`) via a three-step algorithm:
1. Compute the tentative used width (`target`).
2. If the tentative used width is greater than `max-width`, the rules are applied again using the value of `max-width` as the computed value for `width` (effectively clamping the upper bound to `min(max_w, target)`).
3. If the resulting width is smaller than `min-width`, the rules are applied again using the value of `min-width` as the computed value for `width` (effectively clamping the lower bound to `max(min_w, ...)`).

In Chromium Blink (specifically within `ng_length_utils.cc` via `MinMaxSizes::ClampSizeToMinAndMax`), this cascade is collapsed into the canonical closed-form expression:

$$\text{used} = \max(\text{min\_w}, \min(\text{max\_w}, \text{target}))$$

---

### 2. Core Invariants
1. **Unconditional Lower Bound (`used >= min_w`)**: Because the outer operation is $\max(\text{min\_w}, \dots)$, the resolved used size is guaranteed to be at least `min_w` across the entire domain of $\mathbb{Z}$ (or `LayoutUnit`).
2. **Conflict Resolution (`min_w > max_w` $\implies$ `used = min_w`)**: When constraint inputs conflict such that `min_w > max_w`, the inner minimum $\min(\text{max\_w}, \text{target})$ evaluates to a value $\le \text{max\_w} < \text{min\_w}$. The outer maximum therefore strictly selects `min_w`. `min-width` unconditionally overrides `max-width`.
3. **Well-Formed Interval Bounding (`min_w <= max_w`)**: When constraints form a valid non-empty interval, `used` is bounded within $[\text{min\_w}, \text{max\_w}]$.

---

### 3. Concrete Rocq / Coq Verification (`BlinkMinOverridesMaxSizingSemantics.v`)

The following formalization verifies the Blink sizing semantics over integer layout units (`Z`), proving equivalence to the procedural CSS 2.1 §10.4 step-by-step algorithm and establishing all dominance invariants with zero `Admitted` obligations.

```coq
(** * BlinkMinOverridesMaxSizingSemantics.v
    Formal Audit by Agent 235: Chromium Blink Min-Size Overrides Max-Size vs CSS 2.1 §10.4 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkSizingSemantics.

  (** ** 1. Definitions *)

  (** Blink's closed-form sizing formula (e.g., MinMaxSizes::ClampSizeToMinAndMax) *)
  Definition blink_resolve_width (min_w max_w target : Z) : Z :=
    Z.max min_w (Z.min max_w target).

  (** CSS 2.1 §10.4 procedural 3-step algorithm *)
  Definition css21_10_4_procedural (min_w max_w target : Z) : Z :=
    let step1 := target in
    let step2 := if Z.gtb step1 max_w then max_w else step1 in
    let step3 := if Z.ltb step2 min_w then min_w else step2 in
    step3.

  (** ** 2. Equivalence Proof *)

  (** Theorem: Blink's closed-form formula is strictly equivalent to the CSS 2.1 §10.4 algorithm. *)
  Theorem blink_matches_css21_10_4 :
    forall (min_w max_w target : Z),
      blink_resolve_width min_w max_w target = css21_10_4_procedural min_w max_w target.
  Proof.
    intros min_w max_w target.
    unfold blink_resolve_width, css21_10_4_procedural.
    destruct (Z.gtb_spec target max_w) as [Hgt | Hle];
    destruct (Z.ltb_spec (if Z.gtb target max_w then max_w else target) min_w) as [Hlt | Hge];
    try rewrite ( proj2 (Z.gtb_lt target max_w) Hgt ) in *;
    lia.
  Qed.

  (** ** 3. Core Invariant Proofs *)

  (** Invariant 1: The resolved width is ALWAYS >= min_w, regardless of max_w or target. *)
  Theorem used_ge_min_w_always :
    forall (min_w max_w target : Z),
      blink_resolve_width min_w max_w target >= min_w.
  Proof.
    intros min_w max_w target.
    unfold blink_resolve_width.
    lia.
  Qed.

  (** Invariant 2: When min_w > max_w (or min_w >= max_w), min_w completely overrides max_w,
      forcing the used width to be exactly min_w for all targets. *)
  Theorem min_overrides_max_when_inverted :
    forall (min_w max_w target : Z),
      min_w >= max_w ->
      blink_resolve_width min_w max_w target = min_w.
  Proof.
    intros min_w max_w target H_inv.
    unfold blink_resolve_width.
    lia.
  Qed.

  (** Invariant 3: When constraints are well-formed (min_w <= max_w), the used width
      respects both bounds concurrently. *)
  Theorem well_formed_bounds_respected :
    forall (min_w max_w target : Z),
      min_w <= max_w ->
      min_w <= blink_resolve_width min_w max_w target <= max_w.
  Proof.
    intros min_w max_w target H_wf.
    unfold blink_resolve_width.
    lia.
  Qed.

  (** Invariant 4: Target preservation within valid bounds. *)
  Theorem in_bounds_target_preserved :
    forall (min_w max_w target : Z),
      min_w <= target <= max_w ->
      blink_resolve_width min_w max_w target = target.
  Proof.
    intros min_w max_w target H_in.
    unfold blink_resolve_width.
    lia.
  Qed.

  (** Invariant 5: Idempotence of sizing resolution. *)
  Theorem blink_resolve_idempotent :
    forall (min_w max_w target : Z),
      blink_resolve_width min_w max_w (blink_resolve_width min_w max_w target) =
      blink_resolve_width min_w max_w target.
  Proof.
    intros min_w max_w target.
    unfold blink_resolve_width.
    lia.
  Qed.

End BlinkSizingSemantics.
```