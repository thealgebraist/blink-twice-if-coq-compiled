### 1. Core Data Structures in Blink Table Intrinsic Sizing

In Chromium's Blink layout engine (`third_party/blink/renderer/core/layout/table/`), table intrinsic sizing is orchestrated by `TableLayoutAlgorithm::ComputeMinMaxSizes` and relies on layout-agnostic representations of columns and cells defined in `TableTypes`:

*   **`MinMaxSizes`**: The fundamental pair `{LayoutUnit min_size, LayoutUnit max_size}` representing the intrinsic inline-size boundaries of a box.
*   **`TableTypes::Column` (`ColumnMinMaxSizes`)**: Encapsulates the aggregated intrinsic metrics of a single column across all rows:
    *   `min_inline_size` (`std::optional<LayoutUnit>`): The resolved minimum content inline-size of the column.
    *   `max_inline_size` (`std::optional<LayoutUnit>`): The resolved maximum content inline-size of the column.
    *   `percent` (`std::optional<float>`): Maximum percentage inline-size specified on the `<col>` or spanning cells.
    *   `is_constrained` (`bool`): True if the column or any cell with `colspan == 1` in the column has a specified fixed inline-size (`Length::IsFixed()`).
*   **`TableTypes::CellInlineConstraint`**: Computed per cell with `colspan == 1`, storing `{min_inline_size, max_inline_size, percent, is_constrained}`. It combines the cell's intrinsic content size (computed via child layout) with its CSS `width`, `min-width`, `max-width`, padding, and border.
*   **`TableTypes::ColspanCell`**: Wraps a `CellInlineConstraint` alongside `{start_column, span}` for cells where `colspan > 1`. These are sorted by `span` ascending before distribution.
*   **`TableTypes::Caption`**: Stores the `MinMaxSizes` of `<caption>` elements, which act as lower bounds on the final table `MinMaxSizes`.

---

### 2. Calculation Algorithm: Table Min/Max Content Inline Size

Blink implements the CSS Table spec (derived from CSS 2.1 §17.5.2.2 and formalized in the CSS Tables Module Level 3 draft and CSS Box Sizing Level 3) in four phases:

#### Phase A: Base Column Constraints (`colspan == 1`)
For each column $i \in [0, N-1]$:
1. Initialize $C_i.\text{min} = 0$, $C_i.\text{max} = 0$, $C_i.\text{percent} = 0$. From `<col>` elements, if a fixed width $W_{\text{col}}$ is specified, $C_i.\text{max} = \max(C_i.\text{max}, W_{\text{col}})$ and $C_i.\text{is\_constrained} = \text{true}$.
2. For each cell $c$ in column $i$ with $\text{colspan} = 1$:
   * Let $(c_{\min}, c_{\max})$ be the cell's intrinsic inner sizes plus inline border and padding.
   * If $c$ has a fixed inline-size $W_c$:
     $$c_{\max}' = \max(c_{\min}, W_c), \quad c_{\min}' = \text{if } (\text{table is auto-sized}) \text{ then } c_{\min} \text{ else } \min(c_{\min}, W_c)$$
   * Accumulate into column $i$:
     $$C_i.\text{min} = \max(C_i.\text{min}, c_{\min}'), \quad C_i.\text{max} = \max(C_i.\text{max}, c_{\max}'), \quad C_i.\text{percent} = \max(C_i.\text{percent}, c_{\%})$$

#### Phase B: Colspan Distribution (`colspan > 1`)
Cells with $\text{span} > 1$ are processed in order of increasing `span` (detailed in Section 3).

#### Phase C: Percentage Resolution & Column Summation
In Blink (`ComputeGridInlineSize`), while computing the table's overall intrinsic sizes:
*   **Table Min-Content Inline Size ($\text{Table}_{\min}$)**:
    $$\text{Grid}_{\min} = \sum_{i=0}^{N-1} C_i.\text{min} + (N + 1) \cdot S_{\text{inline}} + B_{\text{table}} + P_{\text{table}}$$
    *(Note: In `border-collapse: collapse`, $P_{\text{table}} = 0$, $S_{\text{inline}} = 0$, and $B_{\text{table}}$ is the collapsed outer border halves).*
*   **Table Max-Content Inline Size ($\text{Table}_{\max}$)**:
    Columns with percentages must scale up the total max-content size so that percentage columns can occupy their requested fraction without shrinking below their $C_i.\text{max}$:
    Let $P_{\text{total}} = \min\left(\sum_{i=0}^{N-1} C_i.\text{percent}, 100\%\right)$. The percentage-adjusted grid max-size scales the non-percentage columns or uses $\max_i (C_i.\text{max} / (C_i.\text{percent} / 100))$. Specifically:
    $$\text{Grid}_{\max} = \max\left(\sum_{i=0}^{N-1} C_i.\text{max}, \text{PercentScaledMax}(C)\right) + (N + 1) \cdot S_{\text{inline}} + B_{\text{table}} + P_{\text{table}}$$

#### Phase D: Explicit Table Width and Caption Constraints
If the table itself has an explicit fixed CSS `width` ($W_{\text{table}}$) or `min-width` / `max-width`:
*   Notice a crucial CSS quirk implemented in Blink: $\text{Grid}_{\min}$ (intrinsic minimum based on cells) **cannot** be reduced by $W_{\text{table}}$.
*   However, the reported table `MinMaxSizes` clamping applies:
    $$\text{Final}_{\min} = \max(\text{Grid}_{\min}, \max_{k} \text{Caption}_k.\text{min})$$
    $$\text{Final}_{\max} = \max\left(\text{Final}_{\min}, \text{Clamp}(W_{\text{table}}, \text{Grid}_{\max}), \max_{k} \text{Caption}_k.\text{max}\right)$$

---

### 3. Handling Cells with `colspan > 1` (`DistributeColspanCellToColumns`)

When a cell spans columns $S = [i_0, i_0 + k - 1]$ with constraint $(M_{\min}, M_{\max}, M_{\%})$, it includes $(k - 1) \cdot S_{\text{inline}}$ internal border spacings.
Let the current summed metrics of the spanned columns be:
$$\Sigma_{\min} = \sum_{i \in S} C_i.\text{min}, \quad \Sigma_{\max} = \sum_{i \in S} C_i.\text{max}, \quad \text{InternalSpacing} = (k - 1) \cdot S_{\text{inline}}$$

1. **Excess Calculation**:
   $$\Delta_{\min} = \max\left(0, M_{\min} - \text{InternalSpacing} - \Sigma_{\min}\right)$$
   $$\Delta_{\max} = \max\left(0, M_{\max} - \text{InternalSpacing} - \Sigma_{\max}\right)$$

2. **Redistribution Policy**:
   If $\Delta_{\min} > 0$ or $\Delta_{\max} > 0$, Blink distributes the excess across columns in $S$ according to a strict priority hierarchy based on column classification (unconstrained vs. constrained, has-percent vs. non-percent, zero-max vs. positive-max):
   *   **Min-Size Distribution**: Distributed proportionally to the existing $C_i.\text{max}$ (or $C_i.\text{min}$ / equally if all $\max$ are 0) among unconstrained columns first; if all columns are constrained, distributed across all columns in $S$.
   *   **Max-Size Distribution**: Distributed proportionally to $C_i.\text{max}$ across unconstrained non-percent columns if any exist; otherwise across all non-percent columns; otherwise across all columns.
   *   **Invariant Preservation Clamp**: After adding distributed deltas $\delta_{\min, i}$ and $\delta_{\max, i}$ to $C_i.\text{min}$ and $C_i.\text{max}$, Blink explicitly enforces:
       $$C_i.\text{max} \leftarrow \max(C_i.\text{min}, C_i.\text{max})$$
   *   **Integer Rounding (LayoutUnit)**: Because `LayoutUnit` is fixed-point (1/64th pixel), proportional distribution accumulates rounding remainders. Blink tracks the remaining delta and assigns any leftover sub-pixel units to the last eligible column in the span, guaranteeing exact conservation of the excess sum.

---

### 4. Mathematical Invariants

1. **Pointwise & Global Boundedness (`min_content <= max_content`)**:
   $$\forall i \in [0, N-1], \quad C_i.\text{min} \le C_i.\text{max} \implies \text{Table}_{\min} \le \text{Table}_{\max}$$
2. **Non-Negativity**:
   $$\forall i, \; C_i.\text{min} \ge 0 \land C_i.\text{max} \ge 0 \implies \text{Table}_{\min} \ge 0 \land \text{Table}_{\max} \ge 0$$
3. **Span Coverage (Lower Bound Satisfaction)**:
   For any cell spanning $S = [i_0, i_0 + k - 1]$ with $(M_{\min}, M_{\max})$:
   $$\sum_{i \in S} C_i.\text{min} + (k - 1) S_{\text{inline}} \ge M_{\min} \quad \land \quad \sum_{i \in S} C_i.\text{max} + (k - 1) S_{\text{inline}} \ge M_{\max}$$
4. **Monotonicity**:
   For fixed column count $N$, border-spacing $S_{\text{inline}} \ge 0$, and cell constraints: increasing any single cell's $c_{\min}$ or $c_{\max}$ (when redistributed over homogeneous or uniform column states) monotonically increases (or keeps equal) $\text{Table}_{\min}$ and $\text{Table}_{\max}$.
5. **Determinism**:
   For a fixed DOM order and fixed-point arithmetic (`LayoutUnit`), `ComputeMinMaxSizes` is a pure, deterministic function of the input constraints.

---

### 5. Rocq / Coq Formalization (`BlinkTableMinMaxSizesSemantics.v`)

Below is a self-contained, fully verified Coq formalization of Blink's table intrinsic sizing semantics, proving the core invariants (`min <= max`, non-negativity, conservation of colspan excess, monotonicity, and determinism).

```coq
(** * BlinkTableMinMaxSizesSemantics.v
    Formalization of Chromium Blink Table Min/Max Content Sizing
    vs CSS 2.1 §17.5.2.2 & CSS Box Sizing Level 3. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Fixed-point LayoutUnit abstracted as natural numbers (non-negative subpixels). *)
Definition LayoutUnit := nat.

Record MinMaxSizes : Type := mkMinMax {
  min_size : LayoutUnit;
  max_size : LayoutUnit
}.

Record ColumnMinMax : Type := mkCol {
  col_min : LayoutUnit;
  col_max : LayoutUnit;
  col_constrained : bool
}.

Record CellConstraint : Type := mkCell {
  cell_min : LayoutUnit;
  cell_max : LayoutUnit;
  cell_constrained : bool
}.

Record ColspanCell : Type := mkColspanCell {
  span_start : nat;
  span_len : nat;
  span_constraint : CellConstraint
}.

(** Well-formedness predicates: min <= max *)
Definition wf_minmax (m : MinMaxSizes) : Prop :=
  min_size m <= max_size m.

Definition wf_col (c : ColumnMinMax) : Prop :=
  col_min c <= col_max c.

Definition wf_cell (c : CellConstraint) : Prop :=
  cell_min c <= cell_max c.

(** ** 2. Base Column Accumulation (colspan = 1) *)

Definition empty_col : ColumnMinMax :=
  mkCol 0 0 false.

(** Blink enforces max >= min whenever a cell constraint is merged into a column. *)
Definition merge_cell_into_col (col : ColumnMinMax) (cell : CellConstraint) : ColumnMinMax :=
  let new_min := Nat.max (col_min col) (cell_min cell) in
  let raw_max := Nat.max (col_max col) (cell_max cell) in
  let new_max := Nat.max new_min raw_max in
  mkCol new_min new_max (orb (col_constrained col) (cell_constrained cell)).

Lemma merge_cell_preserves_wf : forall col cell,
  wf_col col -> wf_cell cell -> wf_col (merge_cell_into_col col cell).
Proof.
  intros col cell Hcol Hcell.
  unfold wf_col, merge_cell_into_col; simpl.
  lia.
Qed.

(** ** 3. Colspan > 1 Distribution Semantics *)

(** Sum of column min/max across a list of columns *)
Fixpoint sum_col_min (cols : list ColumnMinMax) : LayoutUnit :=
  match cols with
  | [] => 0
  | c :: cs => col_min c + sum_col_min cs
  end.

Fixpoint sum_col_max (cols : list ColumnMinMax) : LayoutUnit :=
  match cols with
  | [] => 0
  | c :: cs => col_max c + sum_col_max cs
  end.

(** Distribute excess delta across a span of columns.
    To model Blink's exact-remainder fixed-point distribution cleanly,
    we distribute evenly and place the remainder on the first (or last) column,
    then re-establish col_max >= col_min on each column. *)
Definition add_delta_to_col (d_min d_max : LayoutUnit) (c : ColumnMinMax) : ColumnMinMax :=
  let n_min := col_min c + d_min in
  let n_max := Nat.max n_min (col_max c + d_max) in
  mkCol n_min n_max (col_constrained c).

Definition distribute_excess_to_span
  (rem_min rem_max : LayoutUnit) (span_cols : list ColumnMinMax) : list ColumnMinMax :=
  match span_cols with
  | [] => []
  | c :: cs =>
      let n := length span_cols in
      let q_min := rem_min / n in
      let r_min