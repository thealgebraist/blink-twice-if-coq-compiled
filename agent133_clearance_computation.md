### 1. Clearance Calculation (`clearance = max(0, float_bottom - (block_y + margin_top))`)

In CSS 2.1 §9.5.2 (Controlling flow next to floats: the `'clear'` property), clearance is introduced as extra spacing above the `margin-top` of an element when its `'clear'` property requires it to be moved below the bottom outer edge of relevant floating boxes. 

In Chromium Blink’s LayoutNG engine (primarily within `NGBlockLayoutAlgorithm` and `NGExclusionSpace`), clearance is calculated during the BFC (Block Formatting Context) offset resolution phase:

1. **Hypothetical Position Determination**: Blink first computes the hypothetical top border-edge position of the block as if its `'clear'` property were `'none'`. Assuming margins have collapsed (or within a simplified uncollapsed model), the tentative BFC block-offset is:
   $$\text{hypothetical\_y} = \text{block\_y} + \text{margin\_top}$$
2. **Float Bottom Query**: Blink queries the `NGExclusionSpace` via `ClearanceOffset(EClear)` to retrieve the maximum BFC block-end offset ($\text{float\_bottom}$) among all preceding floats in the active formatting context that match the clearance type (`left`, `right`, or `both`).
3. **Clearance Derivation**: If the hypothetical position lies above the relevant float bottom ($\text{hypothetical\_y} < \text{float\_bottom}$), clearance is introduced. Blink computes the exact clearance amount needed to place the block's border edge flush with the float's bottom edge:
   $$\text{clearance} = \max(0, \text{float\_bottom} - (\text{block\_y} + \text{margin\_top}))$$
   *(Note: In CSS 2.1 §9.5.2, clearance can take two possible values due to margin collapsing inhibition, $C_1$ and $C_2$, where $C_1 = \text{float\_bottom} - (\text{block\_y} + \text{margin\_top})$ is the fundamental geometric bound audited here).*

---

### 2. Effective Margin and Cursor Advancement Past Preceding Floats

When clearance is non-zero, it modifies how the layout cursor (`BfcBlockOffset`) advances within the BFC:

* **Effective Margin**: Clearance is structurally distinct from `margin-top`, though it acts similarly by pushing the border box downward. We define the *effective margin* (the total vertical delta from the prior layout cursor $\text{block\_y}$ to the cleared block's top border edge) as:
  $$\text{effective\_margin} = \text{margin\_top} + \text{clearance}$$
  Note that while `margin-top` can be negative, $\text{clearance}$ is strictly non-negative. If `margin-top` is negative, a larger positive clearance is computed to compensate and still reach $\text{float\_bottom}$.
* **Cursor Advancement**: The layout algorithm advances the BFC block-offset cursor to place the block's border box at:
  $$\text{cleared\_block\_y} = \text{block\_y} + \text{effective\_margin} = \text{block\_y} + \text{margin\_top} + \max(0, \text{float\_bottom} - (\text{block\_y} + \text{margin\_top}))$$
  By algebraic simplification ($\text{x} + \max(0, \text{y} - \text{x}) = \max(\text{x}, \text{y})$), the final BFC offset of the block's top border edge is:
  $$\text{cleared\_block\_y} = \max(\text{block\_y} + \text{margin\_top}, \text{float\_bottom})$$
  This guarantees the layout cursor smoothly advances past all relevant preceding floats in the `NGExclusionSpace` before placing the child fragment.

---

### 3. Invariants

The Blink clearance computation upholds three core layout invariants across all layout passes:

1. **Non-negativity of Clearance ($\text{clearance} \ge 0$)**:
   Clearance never pulls a block upward. Even if the block's hypothetical position is already well below the float ($\text{block\_y} + \text{margin\_top} > \text{float\_bottom}$), clearance clamps to $0$.
2. **Float Clearance Guarantee ($\text{cleared\_block\_y} \ge \text{float\_bottom}$)**:
   After applying the effective margin to the layout cursor, the resulting top border edge of the cleared block is guaranteed to be at or below the bottom edge of the cleared floats.
3. **Clearance Monotonicity with respect to Float Bottom**:
   For a fixed $\text{block\_y}$ and $\text{margin\_top}$, if a taller float is encountered (i.e., $\text{float\_bottom}_1 \le \text{float\_bottom}_2$), both the computed clearance and the resulting $\text{cleared\_block\_y}$ are monotonically non-decreasing:
   $$\text{float\_bottom}_1 \le \text{float\_bottom}_2 \implies \text{clearance}_1 \le \text{clearance}_2 \land \text{cleared\_block\_y}_1 \le \text{cleared\_block\_y}_2$$

---

### 4. Rocq/Coq Formalization (`BlinkClearanceComputationSemantics.v`)

Below is the self-contained, fully verified Rocq/Coq formalization of the Blink clearance semantics and its invariants using `ZArith` and `Lia`.

```coq
(** * BlinkClearanceComputationSemantics.v
    Formal Audit of Chromium Blink Clearance Computation vs CSS 2.1 §9.5.2.
    Agent 133 Verification Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkClearanceSemantics.

  (** ** 1. Types and Core Definitions *)

  (** Layout unit representation (e.g., Blink LayoutUnit / CSS pixels in Z) *)
  Definition LayoutUnit := Z.

  (** CSS 'clear' property values *)
  Inductive EClear : Type :=
  | ClearNone
  | ClearLeft
  | ClearRight
  | ClearBoth.

  (** State of preceding floats in Blink's NGExclusionSpace *)
  Record ExclusionSpaceState : Type := mkExclusionSpace {
    left_float_bottom  : LayoutUnit;
    right_float_bottom : LayoutUnit
  }.

  (** Querying the relevant float bottom based on EClear (NGExclusionSpace::ClearanceOffset) *)
  Definition relevant_float_bottom (es : ExclusionSpaceState) (clear_type : EClear) : LayoutUnit :=
    match clear_type with
    | ClearNone  => 0
    | ClearLeft  => left_float_bottom es
    | ClearRight => right_float_bottom es
    | ClearBoth  => Z.max (left_float_bottom es) (right_float_bottom es)
    end.

  (** Hypothetical top border edge before clearance is applied *)
  Definition hypothetical_block_y (block_y margin_top : LayoutUnit) : LayoutUnit :=
    block_y + margin_top.

  (** Core Clearance Calculation:
      clearance = max(0, float_bottom - (block_y + margin_top)) *)
  Definition compute_clearance (block_y margin_top float_bottom : LayoutUnit) : LayoutUnit :=
    Z.max 0 (float_bottom - (block_y + margin_top)).

  (** Effective margin combining margin_top and clearance *)
  Definition compute_effective_margin (block_y margin_top float_bottom : LayoutUnit) : LayoutUnit :=
    margin_top + compute_clearance block_y margin_top float_bottom.

  (** Final BFC block-offset (cursor advancement past floats) *)
  Definition compute_cleared_block_y (block_y margin_top float_bottom : LayoutUnit) : LayoutUnit :=
    block_y + compute_effective_margin block_y margin_top float_bottom.

  (** Context-aware clearance evaluation using ExclusionSpaceState *)
  Definition resolve_bfc_block_offset
    (block_y margin_top : LayoutUnit) (es : ExclusionSpaceState) (c : EClear) : LayoutUnit :=
    match c with
    | ClearNone => hypothetical_block_y block_y margin_top
    | _ => compute_cleared_block_y block_y margin_top (relevant_float_bottom es c)
    end.

  (** ** 2. Structural Lemmas *)

  (** Equivalence between additive clearance and max-cursor advancement *)
  Lemma cleared_block_y_max_equiv :
    forall (block_y margin_top float_bottom : LayoutUnit),
      compute_cleared_block_y block_y margin_top float_bottom =
      Z.max (block_y + margin_top) float_bottom.
  Proof.
    intros block_y margin_top float_bottom.
    unfold compute_cleared_block_y, compute_effective_margin, compute_clearance.
    lia.
  Qed.

  (** When hypothetical position is already at or below float_bottom, clearance is 0 *)
  Lemma clearance_zero_when_below_float :
    forall (block_y margin_top float_bottom : LayoutUnit),
      block_y + margin_top >= float_bottom ->
      compute_clearance block_y margin_top float_bottom = 0.
  Proof.
    intros block_y margin_top float_bottom H.
    unfold compute_clearance.
    lia.
  Qed.

  (** When hypothetical position is above float_bottom, cleared_block_y aligns exactly with float_bottom *)
  Lemma cleared_block_y_exact_on_collision :
    forall (block_y margin_top float_bottom : LayoutUnit),
      block_y + margin_top < float_bottom ->
      compute_cleared_block_y block_y margin_top float_bottom = float_bottom.
  Proof.
    intros block_y margin_top float_bottom H.
    rewrite cleared_block_y_max_equiv.
    lia.
  Qed.

  (** ** 3. Primary Audit Invariants *)

  (** Invariant 1: Clearance is strictly non-negative (clearance >= 0) *)
  Theorem invariant_clearance_non_negative :
    forall (block_y margin_top float_bottom : LayoutUnit),
      compute_clearance block_y margin_top float_bottom >= 0.
  Proof.
    intros block_y margin_top float_bottom.
    unfold compute_clearance.
    lia.
  Qed.

  (** Invariant 2a: Cleared block Y is at or below float_bottom (cleared_block_y >= float_bottom) *)
  Theorem invariant_cleared_block_y_ge_float_bottom :
    forall (block_y margin_top float_bottom : LayoutUnit),
      compute_cleared_block_y block_y margin_top float_bottom >= float_bottom.
  Proof.
    intros block_y margin_top float_bottom.
    rewrite cleared_block_y_max_equiv.
    lia.
  Qed.

  (** Invariant 2b: Cleared block Y never retreats above hypothetical position *)
  Theorem invariant_cleared_block_y_ge_hypothetical :
    forall (block_y margin_top float_bottom : LayoutUnit),
      compute_cleared_block_y block_y margin_top float_bottom >=
      hypothetical_block_y block_y margin_top.
  Proof.
    intros block_y margin_top float_bottom.
    unfold hypothetical_block_y.
    rewrite cleared_block_y_max_equiv.
    lia.
  Qed.

  (** Invariant 3a: Clearance Monotonicity w.r.t. float_bottom *)
  Theorem invariant_clearance_monotonic_in_float_bottom :
    forall (block_y margin_top fb1 fb2 : LayoutUnit),
      fb1 <= fb2 ->
      compute_clearance block_y margin_top fb1 <= compute_clearance block_y margin_top fb2.
  Proof.
    intros block_y margin_top fb1 fb2 H_le.
    unfold compute_clearance.
    lia.
  Qed.

  (** Invariant 3b: Cleared Block Y Monotonicity w.r.t. float_bottom *)
  Theorem invariant_cleared_y_monotonic_in_float_bottom :
    forall (block_y margin_top fb1 fb2 : LayoutUnit),
      fb1 <= fb2 ->
      compute_cleared_block_y block_y margin_top fb1 <=
      compute_cleared_block_y block_y margin_top fb2.
  Proof.
    intros block_y margin_top fb1 fb2 H_le.
    repeat rewrite cleared_block_y_max_equiv.
    lia.
  Qed.

  (** Invariant 3c: Clearance Antitonicity w.r.t. margin_top
      (Larger top margins require less or equal additional clearance) *)
  Theorem invariant_clearance_antitonic_in_margin_top :
    forall (block_y mt1 mt2 float_bottom : LayoutUnit),
      mt1 <= mt2 ->
      compute_clearance block_y mt2 float_bottom <= compute_clearance block_y mt1 float_bottom.
  Proof.
    intros block_y mt1 mt2 float_bottom H_le.
    unfold compute_clearance.
    lia.
  Qed.

  (** Invariant 4: ClearBoth dominates ClearLeft and ClearRight *)
  Theorem invariant_clear_both_dominates :
    forall (block_y margin_top : LayoutUnit) (es : ExclusionSpaceState),
      resolve_bfc_block_offset block_y margin_top es ClearBoth >=
      resolve_bfc_block_offset block_y margin_top es ClearLeft /\
      resolve_bfc_block_offset block_y margin_top es ClearBoth >=
      resolve_bfc_block_offset block_y margin_top es ClearRight.
  Proof.
    intros block_y margin_top es.
    unfold resolve_bfc_block_offset, relevant_float_bottom.
    repeat rewrite cleared_block_y_max_equiv.
    lia.
  Qed.

End BlinkClearanceSemantics.
```