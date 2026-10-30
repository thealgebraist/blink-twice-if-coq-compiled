# Formal Verification Report: Auto-Table Column Width Floor Balancing under Percentage Constraints in Chromium Blink

**Agent:** 699 (W3C/WHATWG Layout Rules — Grid, Tables, Shapes)  
**Topic:** Auto-table column width floor balancing under percentage constraints  
**Chromium Source:** `third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc` (and helper modules `table_layout_utils.cc`)  
**Specification:** CSS 2.1 §17.5.2.2 (Automatic table layout) & CSS Table Module Level 3 §4.2  
**Formal Theory Target:** `BlinkTableAutoLayoutColumnWidthFloorSemantics.v`  
**Core Mathematical Property:** $\text{col\_width} = \max(\text{min\_content}, \min(\text{max\_content}, \text{avail\_share}))$

---

## 1. Exact Normative W3C Specification Requirements

In CSS 2.1 §17.5.2.2 ("Automatic table layout") and its modern formalization in the **CSS Table Module Level 3 (W3C Working Draft)**, automatic table layout (`table-layout: auto`) is governed by a multi-stage constraint solver that balances intrinsic content sizes (`min-content` and `max-content`), fixed length constraints, and percentage width constraints across table columns.

### 1.1 Normative Column Sizing Phases
For any given column $i \in \{0, \dots, N-1\}$, the layout engine computes:
1. **Minimum Content Width ($\text{min\_content}_i \ge 0$):** The smallest width required by any cell originating in column $i$ without overflowing its non-breakable content (or its explicit fixed minimum width).
2. **Maximum Content Width ($\text{max\_content}_i \ge \text{min\_content}_i$):** The width required to lay out the cell's content without any soft line wrapping.
3. **Percentage Constraint ($p_i \in [0, 100\%]$):** The largest percentage width specified on the `<col>` element or any cell spanning column $i$.

### 1.2 The Column Width Floor Balancing Invariant
When distributing the assignable table inline size $W_{\text{avail}}$ across columns:
- **Absolute Floor Rule:** No column may ever be assigned a final width smaller than its $\text{min\_content}_i$, regardless of how aggressive the percentage constraints $p_j$ on other columns are, or how small $W_{\text{avail}}$ is.
- **Percentage Scaling & Clamping:** If the sum of percentage constraints $\sum p_i$ exceeds $100\%$, percentages are scaled down proportionally so their sum equals $100\%$. For a percentage-constrained column, its target share of the table width is bounded below by $\text{min\_content}_i$.
- **Auto / Unconstrained Column Clamping:** When excess available width $\text{avail\_share}_i$ is allocated to a column during the distribution phase (between `min-content` and `max-content` when the table is narrower than its total `max-content`), the assigned column width satisfies the exact clamping lattice equation:
  $$\text{col\_width}_i = \max\Big(\text{min\_content}_i, \min\big(\text{max\_content}_i, \text{avail\_share}_i\big)\Big)$$
  Under percentage constraints, $\text{max\_content}_i$ for a percentage column acts as the resolved percentage target $\max(\text{min\_content}_i, \lfloor p_i \cdot W_{\text{table}} \rfloor)$, ensuring that the floor $\text{min\_content}_i$ is never violated even when $p_i \cdot W_{\text{table}} < \text{min\_content}_i$ or when non-percentage columns are starved of remaining space.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink's LayoutNG Table architecture (`third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc` and `table_layout_utils.cc`, specifically `SynchronizeAssignableTableInlineSizeAndColumns` and `DistributeColspanCellsToColumns`), column width calculation is implemented using fixed-point `LayoutUnit` arithmetic (represented as integer ticks in our formal model).

### 2.1 Execution Pipeline in `table_layout_algorithm.cc`
1. **Column Constraint Extraction (`ComputeColumnConstraints`):**
   Each column is summarized into a `NGTableTypes::Column` struct containing:
   - `min_inline_size` ($\text{min\_content}$)
   - `max_inline_size` ($\text{max\_content}$)
   - `percent` (optional floating-point percentage, clamped so total $\le 100\%$)
   - `is_constrained` (boolean flag for fixed-width columns)
   By construction in `EnforceMinMaxInlineSizes()`, Blink guarantees the structural invariant:
   `min_inline_size >= 0` and `max_inline_size >= min_inline_size`.

2. **Target Inline Size Resolution (`SynchronizeAssignableTableInlineSizeAndColumns`):**
   Given `assignable_table_inline_size` ($W_{\text{avail}}$), Blink classifies columns into buckets (`kMinGuess`, `kPercentageGuess`, `kSpecifiedGuess`, `kMaxGuess`, `kAuto`).
   - **Guess 1 (`kMinGuess`):** Every column starts at `min_inline_size`. If $W_{\text{avail}} \le \sum \text{min\_inline\_size}$, every column immediately receives `min_inline_size` (the table overflows its container, preserving the column width floor).
   - **Guess 2 (`kPercentageGuess`):** Percentage columns are raised to `max(min_inline_size, percent * assignable_table_inline_size)`. Non-percentage columns remain at `min_inline_size`.
   - **Interpolation / Distribution (`DistributeAvailableInlineSize`):** When $W_{\text{avail}}$ lies between two guesses, the available delta is distributed proportionally to the capacity (`max_inline_size - min_inline_size`) of the active column group, yielding a candidate share $\text{avail\_share}_i$ for each column.
   - **Floor & Ceiling Enforcement:** Each column's computed width is clamped via:
     ```cpp
     LayoutUnit col_width = std::max(column.min_inline_size,
                                     std::min(column.max_inline_size, avail_share));
     ```

### 2.2 Critical Blink Layout Invariants
1. **Well-Formedness Preservation:** For every column, if `0 <= min_content <= max_content`, then the resolved `col_width` satisfies `min_content <= col_width <= max_content`.
2. **Idempotence & Monotonicity:** Increasing `avail_share` monotonically increases `col_width` without ever dipping below `min_content`.
3. **Percentage Starvation Immunity:** Even if percentage columns claim $100\%$ of $W_{\text{avail}}$, non-percentage columns receive $\text{avail\_share}_i \le \text{min\_content}_i$, which clamps cleanly to $\text{min\_content}_i$.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkTableAutoLayoutColumnWidthFloorSemantics.v`. It models single-column clamping, percentage target resolution, and multi-column table distribution over arbitrary integer `LayoutUnit` ticks (`Z`).

## 4. Concrete Theorems and Complete Admitted-Free Proofs

```coq
(** * BlinkTableAutoLayoutColumnWidthFloorSemantics.v
    Formal Verification of W3C CSS 2.1 §17.5.2 / CSS Tables 3 Auto-Table
    Column Width Floor Balancing under Percentage Constraints in Chromium Blink
    (third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc)
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Types and Column Constraints *)

(** In Blink, LayoutUnit is a fixed-point integer type (1/64th of a pixel).
    We model LayoutUnit values directly as integers in Z. *)
Definition LayoutUnit := Z.

(** Percentage values are scaled into basis points [0, 10000] representing
    0.00% to 100.00% to maintain exact integer arithmetic, or [0, 100].
    Here we use parts per 10000 (basis points) for high-precision integer layout. *)
Definition BasisPoints : Z := 10000.

Record ColumnConstraint := mkColumn {
  col_min_content : LayoutUnit;
  col_max_content : LayoutUnit;
  col_percent_bp  : Z; (* 0 if no percentage constraint; in [0, 10000] *)
}.

(** A column constraint is well-formed if min_content is non-negative,
    max_content is at least min_content, and percentage is within [0, 100%]. *)
Definition wf_column (c : ColumnConstraint) : Prop :=
  0 <= col_min_content c /\
  col_min_content c <= col_max_content c /\
  0 <= col_percent_bp c <= BasisPoints.

(** ** 2. Core Mathematical Property: Column Width Floor & Ceiling Clamping *)

(** Mathematical Property:
    col_width = max(min_content, min(max_content, avail_share)) *)
Definition compute_col_width
  (min_content max_content avail_share : LayoutUnit) : LayoutUnit :=
  Z.max min_content (Z.min max_content avail_share).

(** Effective upper bound of a column when percentage constraints are active
    given a total assignable table inline size [table_inline_size].
    In Blink's kPercentageGuess / kMaxGuess resolution, a percentage column's
    resolved target is at least its min_content, or its percentage share if larger,
    while an auto column uses its max_content. *)
Definition effective_max_content
  (c : ColumnConstraint) (table_inline_size : LayoutUnit) : LayoutUnit :=
  if Z.eqb (col_percent_bp c) 0 then
    col_max_content c
  else
    let pct_target := (col_percent_bp c * Z.max 0 table_inline_size) / BasisPoints in
    Z.max (col_min_content c) (Z.min (col_max_content c) pct_target).

(** Full single-column width resolution under percentage constraints and
    assigned available share. *)
Definition resolve_column_width
  (c : ColumnConstraint) (table_inline_size avail_share : LayoutUnit) : LayoutUnit :=
  compute_col_width
    (col_min_content c)
    (effective_max_content c table_inline_size)
    avail_share.

(** ** 3. Multi-Column Auto-Table Distribution Model *)

(** Total minimum content width required by a list of columns. *)
Fixpoint sum_min_content (cols : list ColumnConstraint) : LayoutUnit :=
  match cols with
  | [] => 0
  | c :: rest => col_min_content c + sum_min_content rest
  end.

(** Total resolved widths across a list of columns given a list of shares. *)
Fixpoint resolve_all_columns
  (cols : list ColumnConstraint)
  (table_inline_size : LayoutUnit)
  (shares : list LayoutUnit) : list LayoutUnit :=
  match cols, shares with
  | [], _ => []
  | c :: cs, [] =>
      resolve_column_width c table_inline_size 0 :: resolve_all_columns cs table_inline_size []
  | c :: cs, s :: ss =>
      resolve_column_width c table_inline_size s :: resolve_all_columns cs table_inline_size ss
  end.

Fixpoint sum_widths (widths : list LayoutUnit) : LayoutUnit :=
  match widths with
  | [] => 0
  | w :: ws => w + sum_widths ws
  end.

(** ** 4. Fundamental Theorems and Complete Proofs *)

(** Theorem 1: Absolute Floor Guarantee.
    For any min_content, max_content, and avail_share (even negative or starved),
    compute_col_width is always at least min_content. *)
Theorem compute_col_width_floor :
  forall min_content max_content avail_share : LayoutUnit,
    min_content <= compute_col_width min_content max_content avail_share.
Proof.
  intros min_content max_content avail_share.
  unfold compute_col_width.
  lia.
Qed.

(** Theorem 2: Upper Bound (Max-Content Ceiling) Guarantee.
    Whenever min_content <= max_content, compute_col_width never exceeds max_content. *)
Theorem compute_col_width_ceiling :
  forall min_content max_content avail_share : LayoutUnit,
    min_content <= max_content ->
    compute_col_width min_content max_content avail_share <= max_content.
Proof.
  intros min_content max_content avail_share Hle.
  unfold compute_col_width.
  lia.
Qed.

(** Theorem 3: Exact Regime Classification (3-Way Partition).
    Proves that compute_col_width behaves exactly according to the three layout regimes:
    1. Starvation regime (avail_share <= min_content) -> min_content
    2. Flexible regime (min_content <= avail_share <= max_content) -> avail_share
    3. Saturation regime (max_content <= avail_share) -> max_content *)
Theorem compute_col_width_regimes :
  forall min_content max_content avail_share : LayoutUnit,
    min_content <= max_content ->
    (avail_share <= min_content ->
      compute_col_width min_content max_content avail_share = min_content) /\
    (min_content <= avail_share <= max_content ->
      compute_col_width min_content max_content avail_share = avail_share) /\
    (max_content <= avail_share ->
      compute_col_width min_content max_content avail_share = max_content).
Proof.
  intros min_content max_content avail_share Hle.
  unfold compute_col_width.
   repeat split; intros H; lia.
Qed.

(** Theorem 4: Commutativity of Clamping (Lattice Distributivity).
    Swapping the order of floor and ceiling clamping produces the exact same width
    whenever min_content <= max_content. *)
Theorem compute_col_width_clamp_commute :
  forall min_content max_content avail_share : LayoutUnit,
    min_content <= max_content ->
    compute_col_width min_content max_content avail_share =
    Z.min max_content (Z.max min_content avail_share).
Proof.
  intros min_content max_content avail_share Hle.
  unfold compute