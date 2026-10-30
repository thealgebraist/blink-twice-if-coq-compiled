### 1. Audit Summary: Chromium Blink Table Cell `vertical-align: bottom` vs. CSS 2.1 §17.5.3

**Specification Reference (CSS 2.1 §17.5.3 - Table height algorithms):**
> **bottom:** The bottom of the cell box is aligned with the bottom of the last row it spans.

**Chromium Blink Implementation (LayoutNG Table Layout):**
In `third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc` (and helper alignment routines in `table_layout_utils.cc`), once the intrinsic cell block-size (`cell_height`) and the encompassed row block-size (`row_height`) are resolved, the block-start offset (`y_offset`) of the cell content within the table cell's border box is calculated for `EVerticalAlign::kBottom` as:
$$\text{y\_offset} = \text{row\_height} - \text{cell\_height}$$

*(Note: In CSS table layout, the row height is at least as large as the tallest cell in the row, establishing the structural precondition `row_height >= cell_height`. In integer/fixed-point layout units where subtraction could theoretically underflow if unconstrained, or in signed `LayoutUnit` arithmetic, this precondition guarantees non-negativity).*

---

### 2. Core Invariants

Given non-negative layout metrics $\text{row\_height}, \text{cell\_height} \in \mathbb{Z}$ satisfying the table row sizing invariant $\text{row\_height} \ge \text{cell\_height} \ge 0$:

1. **Bottom-Edge Alignment Invariant:**
   $$\text{y\_offset} + \text{cell\_height} = \text{row\_height}$$
   The bottom edge of the positioned cell content coincides exactly with the bottom edge of the row box.

2. **Non-Negative Offset Invariant:**
   $$\text{row\_height} \ge \text{cell\_height} \implies \text{y\_offset} \ge 0$$
   The cell content never overflows above the top edge of the row box.

3. **Boundedness Invariant:**
   $$0 \le \text{y\_offset} \le \text{row\_height}$$
   The vertical offset stays strictly within the vertical bounds of the row.

---

### 3. Rocq / Coq Formalization (`BlinkTableCellVerticalAlignBottomSemantics.v`)

The following file is completely self-contained, uses standard `ZArith` (representing Blink's signed `LayoutUnit` fixed-point representation), and contains **0 admits**.

```coq
(** * BlinkTableCellVerticalAlignBottomSemantics.v
    Formal Audit of Chromium Blink Table Cell Vertical-Align Bottom
    against CSS 2.1 §17.5.3 (Table height algorithms).
    Agent 223 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section TableCellVerticalAlignBottom.

  (** In Chromium Blink, LayoutUnit is a signed fixed-point value.
      We model layout dimensions over Z. *)
  Definition LayoutUnit := Z.

  (** Record representing the resolved vertical geometry of a table cell
      prior to alignment offset application. *)
  Record CellVerticalMetrics := mkCellMetrics {
    row_height  : LayoutUnit;
    cell_height : LayoutUnit;
  }.

  (** Well-formedness predicate corresponding to CSS 2.1 §17.5.3 row height
      resolution: both heights are non-negative, and the row height is at
      least the height of the cell it contains. *)
  Definition wf_cell_metrics (m : CellVerticalMetrics) : Prop :=
    0 <= cell_height m /\ cell_height m <= row_height m.

  (** Blink's calculation for EVerticalAlign::kBottom:
      y_offset = row_height - cell_height *)
  Definition compute_bottom_y_offset (m : CellVerticalMetrics) : LayoutUnit :=
    row_height m - cell_height m.

  (** Theorem 1: Bottom-Edge Alignment Invariant.
      The bottom of the cell content box (y_offset + cell_height)
      aligns exactly with the bottom of the row (row_height). *)
  Theorem bottom_align_exact_sum :
    forall (m : CellVerticalMetrics),
      compute_bottom_y_offset m + cell_height m = row_height m.
  Proof.
    intros m.
    unfold compute_bottom_y_offset.
    lia.
  Qed.

  (** Theorem 2: Non-Negative Offset Invariant.
      Whenever row_height >= cell_height, the computed y_offset is >= 0. *)
  Theorem bottom_align_non_negative :
    forall (m : CellVerticalMetrics),
      cell_height m <= row_height m ->
      0 <= compute_bottom_y_offset m.
  Proof.
    intros m H_le.
    unfold compute_bottom_y_offset.
    lia.
  Qed.

  (** Theorem 3: Full Boundedness under Well-Formed Metrics.
      For any well-formed cell metrics, 0 <= y_offset <= row_height. *)
  Theorem bottom_align_bounds :
    forall (m : CellVerticalMetrics),
      wf_cell_metrics m ->
      0 <= compute_bottom_y_offset m <= row_height m.
  Proof.
    intros m [H_cell_nonneg H_row_ge_cell].
    unfold compute_bottom_y_offset.
    lia.
  Qed.

  (** Theorem 4: Zero Offset Characterization.
      The y_offset is 0 if and only if the cell fills the entire row height. *)
  Theorem bottom_align_zero_iff_full_height :
    forall (m : CellVerticalMetrics),
      compute_bottom_y_offset m = 0 <-> row_height m = cell_height m.
  Proof.
    intros m.
    unfold compute_bottom_y_offset.
    lia.
  Qed.

  (** Bonus: Nat-based formulation (for unsigned layout coordinate pipelines)
      showing that saturating subtraction in nat preserves the exact sum
      invariant when the precondition holds. *)
  Definition compute_bottom_y_offset_nat (row_h cell_h : nat) : nat :=
    (row_h - cell_h)%nat.

  Theorem bottom_align_nat_invariants :
    forall (row_h cell_h : nat),
      (cell_h <= row_h)%nat ->
      (compute_bottom_y_offset_nat row_h cell_h + cell_h = row_h)%nat /\
      (0 <= compute_bottom_y_offset_nat row_h cell_h)%nat.
  Proof.
    intros row_h cell_h H_le.
    unfold compute_bottom_y_offset_nat.
    lia.
  Qed.

End TableCellVerticalAlignBottom.
```