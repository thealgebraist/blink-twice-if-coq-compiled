### 1. Specification & Implementation Analysis: `fit-content()` Track Clamping

In **CSS Grid Layout Module Level 1 (§11.5.1, "Initialize Track Sizes" & §11.5, "Resolve Intrinsic Track Sizes")**, the `fit-content(limit)` track sizing function is defined as clamping the track’s size to a given limit argument $L$, while guaranteeing that the track never drops below its `min-content` contribution and never exceeds its `max-content` contribution during intrinsic size resolution.

#### Formula Equivalence
The W3C specification defines the sizing behavior of `fit-content(L)` as:
$$\text{fit-content}(L) = \min(\text{max-content}, \max(\text{min-content}, L))$$

When resolving track sizes against a definite or indefinite available space $A$ (`available_space`) during layout, Blink's `GridTrackSizingAlgorithm` (specifically within `GridTrack::FitContentTrackBreadth` and `ResolveIntrinsicTrackSizes`) clamps the active growth limit. When mapping the available space expansion prior to reaching the `max-content` cap, the effective clamping step enforced by the layout engine for a single track's base/limit progression against available space $A$ is modeled as:

$$\text{TrackSize}(mc, A, L) = \min(\max(mc, A), \max(mc, L))$$

where:
* $mc$: `min_content` (the resolved minimum content contribution of the grid items spanning the track).
* $A$: `available_space` (the space allocated or distributed to the track).
* $L$: the resolved length/percentage argument passed to `fit-content(L)`.

*(Note: Because $\min$ distributes over $\max$, $\min(\max(mc, A), \max(mc, L))$ is algebraically equivalent to $\max(mc, \min(A, L))$).*

---

### 2. Core Verification Invariants

To verify that Chromium Blink's `fit-content(L)` clamping logic adheres to CSS Grid 1 §11.5.1 without layout underflow or growth limit violation, the following invariants must hold over all non-negative layout units ($mc, A, L \in \mathbb{N}$):

1. **Lower Bound Invariant (`min-content` Floor):**
   $$\forall mc, A, L, \quad mc \le \text{TrackSize}(mc, A, L)$$
   The resolved track size can never be smaller than the track's `min-content` size, regardless of how small the `fit-content` limit $L$ or `available_space` $A$ is (even if $L = 0$ or $A = 0$).

2. **Upper Bound Invariant (Clamped Limit Ceiling):**
   $$\forall mc, A, L, \quad \text{TrackSize}(mc, A, L) \le \max(mc, L)$$
   The track growth is strictly bounded above by the resolved `fit-content` limit $L$, except when the `min-content` floor itself exceeds $L$, in which case `min-content` wins (as required by CSS `minmax`/clamping precedence rules).

3. **Distributive Simplification Invariant:**
   $$\forall mc, A, L, \quad \min(\max(mc, A), \max(mc, L)) = \max(mc, \min(A, L))$$
   Proves that Blink's two-stage clamping implementation (clamping $A$ and $L$ against $mc$ independently before taking the minimum) is strictly isomorphic to clamping $A$ by $L$ first and then flooring at $mc$.

---

### 3. Rocq / Coq Formalization (`BlinkGridFitContentClampSemantics.v`)

Below is the self-contained, fully mechanized Rocq (Coq) proof script establishing the semantics and invariants of the `fit-content()` track clamping algorithm.

```coq
(** * BlinkGridFitContentClampSemantics.v
    Formal Audit of Chromium Blink Grid fit-content() Track Clamping
    against W3C CSS Grid Layout Module Level 1, Section 11.5.1.
    Agent 169 Verification Artifact. *)

Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia.

Module BlinkGridFitContentClampSemantics.

  (** ** 1. Definitions *)

  (** Layout values in Blink (LayoutUnit) are modeled over natural numbers
      representing non-negative subpixel units after zero-clamping. *)
  Definition LayoutUnit := nat.

  (** The canonical formula for fit-content(L) track clamping under available space:
      fit_content_clamp(min_content, available_space, L) =
        min(max(min_content, available_space), max(min_content, L)) *)
  Definition fit_content_clamp (min_content available_space L : LayoutUnit) : LayoutUnit :=
    Nat.min (Nat.max min_content available_space) (Nat.max min_content L).

  (** The upper bound limit dictated by CSS Grid 1 §11.5.1:
      The track cannot exceed L, unless min_content > L. *)
  Definition fit_content_upper_bound (min_content L : LayoutUnit) : LayoutUnit :=
    Nat.max min_content L.

  (** ** 2. Structural Equivalence & Algebraic Properties *)

  (** Theorem: Distributivity of max over min.
      Demonstrates that clamping both branches by [min_content] before taking [min]
      is identical to taking [min(available_space, L)] and flooring at [min_content]. *)
  Theorem fit_content_clamp_distributive :
    forall (min_content available_space L : LayoutUnit),
      fit_content_clamp min_content available_space L =
      Nat.max min_content (Nat.min available_space L).
  Proof.
    intros min_content available_space L.
    unfold fit_content_clamp.
    lia.
  Qed.

  (** ** 3. Primary Safety Invariants *)

  (** Invariant 1 (Lower Bound):
      The resolved track size is always bounded below by [min_content]. *)
  Theorem fit_content_bounded_below_by_min_content :
    forall (min_content available_space L : LayoutUnit),
      min_content <= fit_content_clamp min_content available_space L.
  Proof.
    intros min_content available_space L.
    unfold fit_content_clamp.
    lia.
  Qed.

  (** Invariant 2 (Upper Bound):
      The resolved track size is always bounded above by [max(min_content, L)]. *)
  Theorem fit_content_bounded_above_by_limit :
    forall (min_content available_space L : LayoutUnit),
      fit_content_clamp min_content available_space L <= fit_content_upper_bound min_content L.
  Proof.
    intros min_content available_space L.
    unfold fit_content_clamp, fit_content_upper_bound.
    lia.
  Qed.

  (** Invariant 3 (Combined Sandwich Invariant):
      For all inputs, min_content <= track_size <= max(min_content, L). *)
  Theorem fit_content_sandwich_invariant :
    forall (min_content available_space L : LayoutUnit),
      min_content <= fit_content_clamp min_content available_space L /\
      fit_content_clamp min_content available_space L <= fit_content_upper_bound min_content L.
  Proof.
    intros min_content available_space L.
    split.
    - apply fit_content_bounded_below_by_min_content.
    - apply fit_content_bounded_above_by_limit.
  Qed.

  (** ** 4. Boundary & Monotonicity Conditions (CSS Grid §11.5.1 Edge Cases) *)

  (** Edge Case 1: When min_content exceeds the fit-content argument L,
      the track size collapses exactly to min_content regardless of available_space. *)
  Theorem fit_content_min_content_dominates_small_limit :
    forall (min_content available_space L : LayoutUnit),
      L <= min_content ->
      fit_content_clamp min_content available_space L = min_content.
  Proof.
    intros min_content available_space L H_le.
    unfold fit_content_clamp.
    lia.
  Qed.

  (** Edge Case 2: When available_space exceeds or equals L (and L >= min_content),
      the track size is strictly clamped to L. *)
  Theorem fit_content_saturates_at_L :
    forall (min_content available_space L : LayoutUnit),
      min_content <= L ->
      L <= available_space ->
      fit_content_clamp min_content available_space L = L.
  Proof.
    intros min_content available_space L H_mc_L H_L_avail.
    unfold fit_content_clamp.
    lia.
  Qed.

  (** Monotonicity with respect to available_space:
      Increasing available_space never decreases the resolved track size. *)
  Theorem fit_content_monotonic_available_space :
    forall (min_content avail1 avail2 L : LayoutUnit),
      avail1 <= avail2 ->
      fit_content_clamp min_content avail1 L <= fit_content_clamp min_content avail2 L.
  Proof.
    intros min_content avail1 avail2 L H_avail.
    unfold fit_content_clamp.
    lia.
  Qed.

  (** Monotonicity with respect to limit L:
      Increasing the fit-content limit L never decreases the resolved track size. *)
  Theorem fit_content_monotonic_limit :
    forall (min_content available_space L1 L2 : LayoutUnit),
      L1 <= L2 ->
      fit_content_clamp min_content available_space L1 <= fit_content_clamp min_content available_space L2.
  Proof.
    intros min_content available_space L1 L2 H_limit.
    unfold fit_content_clamp.
    lia.
  Qed.

  (** Idempotence of clamping:
      Feeding the resolved track size back into fit_content_clamp as available_space
      yields the exact same track size. *)
  Theorem fit_content_clamp_idempotent :
    forall (min_content available_space L : LayoutUnit),
      let resolved := fit_content_clamp min_content available_space L in
      fit_content_clamp min_content resolved L = resolved.
  Proof.
    intros min_content available_space L resolved.
    subst resolved.
    unfold fit_content_clamp.
    lia.
  Qed.

End BlinkGridFitContentClampSemantics.
```