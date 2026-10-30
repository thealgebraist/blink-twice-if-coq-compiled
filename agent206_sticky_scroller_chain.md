### Audit Report: Agent 206 — Chromium Blink Nested Sticky Constraints vs. CSS Positioned Layout Module Level 3 §6

---

### 1. Cumulative Sticky Offset Mechanics

In Chromium Blink (` StickyPositionScrollingConstraints::ComputeStickyOffset`), a sticky-positioned element inside nested scroll containers accumulates offsets across its scroller ancestor chain. While CSS Positioned Layout Module Level 3 §6 defines sticky positioning relative to the *nearest* scrollport, nested sticky elements (or sticky elements referencing intermediate sticky ancestors/scrollers) induce a chained constraint resolution in the compositor and layout trees.

#### Mathematical Formulation
For a 1D projection (e.g., the block/vertical axis) over a chain of two nested scroll containers $S_1$ (inner) and $S_2$ (outer), let the unshifted sticky constraint intervals be $[min_1, max_1]$ and $[min_2, max_2]$ where $min_i \le max_i$. Let the respective scroll offsets be $scroll_1, scroll_2 \in \mathbb{Z}$.

The clamping operator is defined as:
$$\text{clamp}(min, max, val) = \max(min, \min(max, val))$$

The individual sticky offsets contributed by each scroller are:
$$\delta_1 = \text{clamp}(min_1, max_1, scroll_1)$$
$$\delta_2 = \text{clamp}(min_2, max_2, scroll_2)$$

The **Cumulative Sticky Offset** ($\Delta_{\text{total}}$) applied to the target box in the root coordinate space (modulo ancestor box shifts) is the linear superposition of the clamped scroll contributions:
$$\Delta_{\text{total}}(scroll_1, scroll_2) = \text{clamp}(min_1, max_1, scroll_1) + \text{clamp}(min_2, max_2, scroll_2)$$

*(Audit Note: Blink tracks `total_sticky_box_sticky_offset` and `total_containing_block_sticky_offset` in `StickyPositionScrollingConstraints` to avoid double-counting when ancestors themselves are sticky. When decoupled across purely nested scrollports, the offset reduces strictly to this additive clamping sum).*

---

### 2. Core Invariants

To guarantee layout stability, compositor thread synchronization, and absence of oscillation during asynchronous scrolling, the cumulative offset calculation must satisfy two foundational invariants:

#### Invariant A: Cumulative Offset Bounded by Sum of Individual Bounds
Assuming valid layout box constraints where the containing block is at least as large as the sticky view rectangle ($min_1 \le max_1$ and $min_2 \le max_2$), the total offset cannot exceed the sum of the maximum allowed adjustments of each scroller, nor fall below the sum of the minimum adjustments:
$$min_1 + min_2 \le \Delta_{\text{total}}(scroll_1, scroll_2) \le max_1 + max_2$$

#### Invariant B: Monotonicity in Individual Scrollers
Scrolling either the inner or outer container in a positive direction (increasing $scroll_i$) must never cause the sticky element to move backward in sticky offset space. Because $\text{clamp}$ is monotonically non-decreasing with respect to its value argument, and addition preserves monotonicity:
$$\forall s_1, s_1', s_2, s_2', \quad s_1 \le s_1' \land s_2 \le s_2' \implies \Delta_{\text{total}}(s_1, s_2) \le \Delta_{\text{total}}(s_1', s_2')$$

---

### 3. Formal Verification: `BlinkStickyScrollerChainSemantics.v`

Below is the complete, self-contained Rocq (Coq) formalization proving the clamping mechanics, additive bounding invariants, and multi-scroller monotonicity over $\mathbb{Z}$.

```coq
(** * BlinkStickyScrollerChainSemantics.v
    Formal Audit by Agent 206: Chromium Blink Nested Sticky Constraints
    vs. CSS Positioned Layout Module Level 3 §6.
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

Module BlinkStickyScrollerChainSemantics.

  (** ** 1. Core Definitions *)

  (** Standard clamping operator: clamp(min_v, max_v, val) *)
  Definition clamp (min_v max_v val : Z) : Z :=
    Z.max min_v (Z.min max_v val).

  (** Record representing the 1D sticky boundaries for a single scroller.
      In Blink, these correspond to the delta limits between the sticky box 
      and its containing block within the scrollport constraint rect. *)
  Record StickyBounds := mkBounds {
    sb_min : Z;
    sb_max : Z;
    sb_valid : sb_min <= sb_max
  }.

  (** Single scroller sticky offset contribution *)
  Definition single_sticky_offset (b : StickyBounds) (scroll : Z) : Z :=
    clamp (sb_min b) (sb_max b) scroll.

  (** Cumulative sticky offset for a 2-scroller chain:
      offset = clamp(min1, max1, scroll1) + clamp(min2, max2, scroll2) *)
  Definition cumulative_sticky_offset 
    (b1 b2 : StickyBounds) (scroll1 scroll2 : Z) : Z :=
    single_sticky_offset b1 scroll1 + single_sticky_offset b2 scroll2.


  (** ** 2. Fundamental Lemmas for Clamp *)

  (** Clamp is bounded below by min_v and above by max_v when min_v <= max_v. *)
  Lemma clamp_bounds : forall min_v max_v val : Z,
    min_v <= max_v ->
    min_v <= clamp min_v max_v val <= max_v.
  Proof.
    intros min_v max_v val Hvalid.
    unfold clamp.
    lia.
  Qed.

  (** Clamp is monotonically non-decreasing with respect to the scroll value. *)
  Lemma clamp_monotonic : forall min_v max_v val1 val2 : Z,
    val1 <= val2 ->
    clamp min_v max_v val1 <= clamp min_v max_v val2.
  Proof.
    intros min_v max_v val1 val2 Hle.
    unfold clamp.
    lia.
  Qed.

  (** Clamp is idempotent within valid bounds. *)
  Lemma clamp_idempotent : forall min_v max_v val : Z,
    min_v <= max_v ->
    clamp min_v max_v (clamp min_v max_v val) = clamp min_v max_v val.
  Proof.
    intros min_v max_v val Hvalid.
    unfold clamp.
    lia.
  Qed.


  (** ** 3. Audit Invariant Theorems *)

  (** Theorem 1 (Individual Bounds): 
      A single scroller's sticky offset is strictly within its StickyBounds. *)
  Theorem single_offset_bounded : forall (b : StickyBounds) (scroll : Z),
    sb_min b <= single_sticky_offset b scroll <= sb_max b.
  Proof.
    intros b scroll.
    unfold single_sticky_offset.
    apply clamp_bounds.
    exact (sb_valid b).
  Qed.

  (** Theorem 2 (Cumulative Bounds Invariant): 
      The cumulative sticky offset across two nested scrollers is bounded 
      by the sum of the individual minimum bounds and the sum of the 
      individual maximum bounds. *)
  Theorem cumulative_offset_bounded : 
    forall (b1 b2 : StickyBounds) (scroll1 scroll2 : Z),
      sb_min b1 + sb_min b2 <= cumulative_sticky_offset b1 b2 scroll1 scroll2 <= sb_max b1 + sb_max b2.
  Proof.
    intros b1 b2 scroll1 scroll2.
    unfold cumulative_sticky_offset.
    pose proof (single_offset_bounded b1 scroll1) as H1.
    pose proof (single_offset_bounded b2 scroll2) as H2.
    lia.
  Qed.

  (** Theorem 3 (Partial Monotonicity - Inner Scroller): 
      Increasing scroll1 while holding scroll2 constant never decreases 
      the cumulative sticky offset. *)
  Theorem cumulative_monotonic_left :
    forall (b1 b2 : StickyBounds) (s1 s1' s2 : Z),
      s1 <= s1' ->
      cumulative_sticky_offset b1 b2 s1 s2 <= cumulative_sticky_offset b1 b2 s1' s2.
  Proof.
    intros b1 b2 s1 s1' s2 Hle.
    unfold cumulative_sticky_offset, single_sticky_offset.
    pose proof (clamp_monotonic (sb_min b1) (sb_max b1) s1 s1' Hle) as Hmono1.
    lia.
  Qed.

  (** Theorem 4 (Partial Monotonicity - Outer Scroller): 
      Increasing scroll2 while holding scroll1 constant never decreases 
      the cumulative sticky offset. *)
  Theorem cumulative_monotonic_right :
    forall (b1 b2 : StickyBounds) (s1 s2 s2' : Z),
      s2 <= s2' ->
      cumulative_sticky_offset b1 b2 s1 s2 <= cumulative_sticky_offset b1 b2 s1 s2'.
  Proof.
    intros b1 b2 s1 s2 s2' Hle.
    unfold cumulative_sticky_offset, single_sticky_offset.
    pose proof (clamp_monotonic (sb_min b2) (sb_max b2) s2 s2' Hle) as Hmono2.
    lia.
  Qed.

  (** Theorem 5 (Joint Scroller Monotonicity Invariant): 
      Simultaneous non-decreasing scroll updates across both scrollers 
      preserve the non-decreasing invariant of the cumulative sticky offset. *)
  Theorem cumulative_monotonic_joint :
    forall (b1 b2 : StickyBounds) (s1 s1' s2 s2' : Z),
      s1 <= s1' ->
      s2 <= s2' ->
      cumulative_sticky_offset b1 b2 s1 s2 <= cumulative_sticky_offset b1 b2 s1' s2'.
  Proof.
    intros b1 b2 s1 s1' s2 s2' Hle1 Hle2.
    apply Z.le_trans with (m := cumulative_sticky_offset b1 b2 s1' s2).
    - apply cumulative_monotonic_left; exact Hle1.
    - apply cumulative_monotonic_right; exact Hle2.
  Qed.

  (** ** 4. Generalization to N-Scroller Chains *)

  Require Import Coq.Lists.List.
  Import ListNotations.

  (** Generalized N-scroller chain cumulative offset *)
  Fixpoint chain_sticky_offset (chain : list (StickyBounds * Z)) : Z :=
    match chain with
    | [] => 0
    | (b, s) :: rest => single_sticky_offset b s + chain_sticky_offset rest
    end.

  Fixpoint sum_min_bounds (chain : list (StickyBounds * Z)) : Z :=
    match chain with
    | [] => 0
    | (b, _) :: rest => sb_min b + sum_min_bounds rest
    end.

  Fixpoint sum_max_bounds (chain : list (StickyBounds * Z)) : Z :=
    match chain with
    | [] => 0
    | (b, _) :: rest => sb_max b + sum_max_bounds rest
    end.

  (** Theorem 6 (N-Chain Boundedness):
      For any arbitrary depth of nested scrollers, the total cumulative offset 
      is bounded by the sum of all minimum bounds and maximum bounds in the chain. *)
  Theorem chain_offset_bounded : forall (chain : list (StickyBounds * Z)),
    sum_min_bounds chain <= chain_sticky_offset chain <= sum_max_bounds chain.
  Proof.
    induction chain as [| [b s] rest IH].
    - simpl. lia.
    - simpl.
      pose proof (single_offset_bounded b s) as Hb.
      lia.
  Qed.

End BlinkStickyScrollerChainSemantics.
```