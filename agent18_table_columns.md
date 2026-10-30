### 1. Core Data Structures in Blink Column Sizing

In Chromium's Blink LayoutNG engine (`third_party/blink/renderer/core/layout/table/`), table column sizing is orchestrated primarily by `TableTypes`, `TableLayoutUtils`, and `TableLayoutAlgorithm`. The historical `TableColumnTracker` and `TableColumnGrouping` mechanisms are represented via flattened constraint descriptors and output location vectors:

*   **`TableTypes::Column` (The Column Constraint Descriptor / Tracker):**
    Aggregates sizing constraints from `<col>`, `<colgroup>`, and `<td/th>` elements for a single structural column index.
    *   `min_inline_size` (`std::optional<LayoutUnit>`): The resolved minimum content inline size required by cells spanning this column.
    *   `max_inline_size` (`std::optional<LayoutUnit>`): The resolved maximum content inline size (or preferred fixed width) required by cells or `<col>` specifications.
    *   `percentage_inline_size` (`std::optional<float>`): Percentage width specified via CSS on the `<col>` or cells.
    *   `is_constrained` (`bool`): True if the column has a specified fixed (`<length>`) or percentage width.
    *   `is_collapsed` (`bool`): True if the column has `visibility: collapse`.

*   **`TableTypes::Columns` (`TableColumnGrouping` & Tracker Container):**
    A `WTF::Vector<TableTypes::Column>` representing the canonical grid of columns. Before width distribution, `TableLayoutUtils::ComputeColumnConstraints` populates this vector by:
    1. Extracting constraints from `<colgroup>` and `<col>` layout objects (`Colspan` expansion flattens `<colgroup span="N">` into $N$ discrete `Column` records).
    2. Iterating over cells with `colspan == 1` to bound `min_inline_size`, `max_inline_size`, and `percentage_inline_size`.
    3. Distributing constraints from `colspan > 1` cells across spanned `Column` entries via `DistributeColspanCellToColumns`.

*   **`TableColumnLocation`:**
    The output geometry record produced by `SynchronizeAssignableTableInlineSizeAndColumns` and consumed during box fragment generation and cell placement (`table_layout_algorithm_types.h`):
    *   `offset` (`LayoutUnit`): The inline-axis offset of the column relative to the table's border box (incorporating initial border-spacing and cumulative preceding column widths and spacings).
    *   `size` (`LayoutUnit`): The final computed inline size of the column.
    *   `is_collapsed` (`bool`): Indicates whether this column's geometry was zeroed out due to `visibility: collapse`.

---

### 2. Column Width Resolution Algorithm: Fixed vs. Auto Layout

Blink implements CSS 2.1 §17.5.2.1 (Fixed table layout) and §17.5.2.2 / CSS Table Module Level 3 (Automatic table layout) in `TableLayoutUtils`.

#### A. Fixed Layout (`table-layout: fixed`)
Triggered when `Style().IsFixedTableLayout()` is true and the table has a definite inline size (not `auto`).
1.  **Constraint Harvesting:** Only `<col>`/`<colgroup>` elements and cells originating in the **first row** of the table are inspected. Cells in subsequent rows are ignored for column sizing.
2.  **Initial Assignment:**
    *   Columns with `<length>` widths get `size = fixed_width`.
    *   Columns with `<percentage>` widths get `size = percentage * assignable_table_inline_size`.
    *   Columns with `auto` width are marked as unassigned (`std::nullopt`).
    *   If a first-row cell has `colspan = N`, its specified width (minus $N-1$ border-spacings) is divided equally among the $N$ spanned columns.
3.  **Distribution:**
    Let $W_{\text{avail}}$ be the assignable table inline size (table content inline size minus $(C + 1) \times \text{border\_spacing}$). Let $W_{\text{assigned}}$ be the sum of fixed and percentage column widths.
    *   **Case 1 ($W_{\text{assigned}} < W_{\text{avail}}$ and count of `auto` columns $N_{\text{auto}} > 0$):**
        Remaining space $\Delta = W_{\text{avail}} - W_{\text{assigned}}$ is divided equally among the $N_{\text{auto}}$ auto columns:
        $$W_i = \frac{\Delta}{N_{\text{auto}}}$$
    *   **Case 2 ($W_{\text{assigned}} < W_{\text{avail}}$ and $N_{\text{auto}} = 0$):**
        All columns have specified widths, but their sum is less than the table width. Blink scales up all non-zero columns proportionally to absorb $\Delta$:
        $$W_i' = W_i + \Delta \cdot \frac{W_i}{W_{\text{assigned}}}$$
    *   **Case 3 ($W_{\text{assigned}} \ge W_{\text{avail}}$):**
        `auto` columns receive `0px`. Fixed and percentage columns retain their computed widths (forcing the table's final inline size to expand to $W_{\text{assigned}}$, overflowing the specified table width per CSS 2.1 §17.5.2.1).

#### B. Auto Layout (`table-layout: auto`)
Implemented in `DistributeTableInlineSizeToComputedInlineSizeAuto`. Every column $i$ has a lower bound $m_i = \text{min\_inline\_size}$, a preferred bound $M_i = \text{max\_inline\_size}$ (where $M_i \ge m_i$), and an optional percentage $P_i \in (0, 100]$.
Let $W_{\text{avail}}$ be the target assignable inline size.

1.  **Minimum Bound Guarantee:**
    Let $M_{\min} = \sum_i m_i$. If $W_{\text{avail}} \le M_{\min}$, no excess space exists; every column receives its minimum inline size: $W_i = m_i$.
2.  **Excess Space Distribution ($W_{\text{avail}} > M_{\min}$):**
    Columns are partitioned into four priority classes:
    *   $\mathcal{C}_{\text{percent}}$: Columns with $P_i > 0$.
    *   $\mathcal{C}_{\text{fixed}}$: Constrained columns (`is_constrained == true`) without percentages.
    *   $\mathcal{C}_{\text{auto}}$: Unconstrained columns with $M_i > 0$.
    *   $\mathcal{C}_{\text{empty}}$: Unconstrained columns with $M_i = 0$.

    Blink distributes $W_{\text{avail}}$ through progressive water-filling stages, ensuring no column shrinks below $m_i$. When excess space $\Delta$ is distributed across a candidate set $\mathcal{S}$:
    *   If distributing toward max-content, the weight for column $i \in \mathcal{S}$ is based on **growth potential** $\text{guess\_diff}_i = M_i - m_i$ (or $M_i$ if all columns in $\mathcal{S}$ are already at $M_i$).
    *   $$W_i = m_i + \Delta \cdot \frac{M_i - m_i}{\sum_{j \in \mathcal{S}} (M_j - m_j)}$$

---

### 3. Competition Between Percentage, Fixed, and Auto Columns

In Blink's `SynchronizeAssignableTableInlineSizeAndColumns`, the competition for $W_{\text{avail}}$ is resolved using a piecewise linear interpolation ("guesses") approach. Blink defines four canonical layout states (guesses) for the column vector:

1.  **`kMinGuess`:** Every column is at $m_i$.
    $$\text{Guess}_1(i) = m_i$$
2.  **`kPercentageGuess`:** Percentage columns expand to $\max(m_i, P_i \cdot W_{\text{avail}})$ (note: total percentages are clamped so $\sum P_i \le 100\%$). Non-percentage columns remain at $m_i$.
    $$\text{Guess}_2(i) = \begin{cases} \max(m_i, P_i \cdot W_{\text{avail}}) & i \in \mathcal{C}_{\text{percent}} \\ m_i & \text{otherwise} \end{cases}$$
3.  **`kSpecifiedGuess`:** Percentage columns stay at $\text{Guess}_2(i)$, fixed columns ($\mathcal{C}_{\text{fixed}}$) expand to $M_i$, and auto columns remain at $m_i$.
    $$\text{Guess}_3(i) = \begin{cases} \text{Guess}_2(i) & i \in \mathcal{C}_{\text{percent}} \\ M_i & i \in \mathcal{C}_{\text{fixed}} \\ m_i & i \in \mathcal{C}_{\text{auto}} \cup \mathcal{C}_{\text{empty}} \end{cases}$$
4.  **`kMaxGuess`:** All columns expand to their maximums ($\text{Guess}_2(i)$ for percentage columns, $M_i$ for fixed and auto columns).
    $$\text{Guess}_4(i) = \begin{cases} \text{Guess}_2(i) & i \in \mathcal{C}_{\text{percent}} \\ M_i & \text{otherwise} \end{cases}$$

Let $S_k = \sum_i \text{Guess}_k(i)$ for $k \in \{1, 2, 3, 4\}$. Since $m_i \le M_i$ and $\text{Guess}_2(i) \ge m_i$, we have the invariant $S_1 \le S_2 \le S_3 \le S_4$.

*   **If $W_{\text{avail}} \in [S_1, S_2]$:** Only $\mathcal{C}_{\text{percent}}$ columns grow from $m_i$ toward $\text{Guess}_2(i)$, proportional to $\text{Guess}_2(i) - m_i$.
*   **If $W_{\text{avail}} \in (S_2, S_3]$:** $\mathcal{C}_{\text{percent}}$ columns are locked at $\text{Guess}_2(i)$. $\mathcal{C}_{\text{fixed}}$ columns grow from $m_i$ toward $M_i$, proportional to $M_i - m_i$.
*   **If $W_{\text{avail}} \in (S_3, S_4]$:** $\mathcal{C}_{\text{percent}}$ and $\mathcal{C}_{\text{fixed}}$ are locked at $\text{Guess}_3(i)$. $\mathcal{C}_{\text{auto}}$ columns grow from $m_i$ toward $M_i$, proportional to $M_i - m_i$.
*   **If $W_{\text{avail}} > S_4$:** All columns start at $\text{Guess}_4(i)$. The remaining excess $\Delta_{\text{rem}} = W_{\text{avail}} - S_4$ is distributed according to strict fallback hierarchy:
    1. If $\mathcal{C}_{\text{auto}} \neq \emptyset$, distribute $\Delta_{\text{rem}}$ to $\mathcal{C}_{\text{auto}}$ proportional to $M_i$.
    2. Else if $\mathcal{C}_{\text{empty}} \neq \emptyset$, distribute $\Delta_{\text{rem}}$ equally among $\mathcal{C}_{\text{empty}}$.
    3. Else if $\mathcal{C}_{\text{fixed}} \neq \emptyset$, distribute $\Delta_{\text{rem}}$ to $\mathcal{C}_{\text{fixed}}$ proportional to $M_i$.
    4. Else if $\mathcal{C}_{\text{percent}} \neq \emptyset$, distribute $\Delta_{\text{rem}}$ to $\mathcal{C}_{\text{percent}}$ proportional to $P_i$.

*Note on Discretization:* Because `LayoutUnit` is fixed-point (1/64th pixel), proportional division introduces rounding remainders. Blink tracks `computed_inline_size_sum` and sweeps any subpixel remainder $\pm \epsilon$ across columns in a final pass to guarantee exact conservation of inline size.

---

### 4. Mathematical Invariants

For any column vector $C = [c_1, \dots, c_n]$ with $n \ge 1$ where each $c_i$ satisfies $0 \le m_i \le M_i$, and for any assignable table inline size $W_{\text{avail}} \ge 0$:

1.  **Minimum Content Preservation (Lower Bound Invariant):**
    In `table-layout: auto`, no column is ever sized smaller than its minimum content inline size:
    $$\forall i \in \{1, \dots, n\},\quad W_i(W_{\text{avail}}) \ge m_i$$

2.  **Inline Space Conservation (Exact Sum Invariant):**
    Whenever the assignable table inline size is at least the sum of minimum column widths ($W_{\text{avail}} \ge \sum_{i=1}^n m_i$) and $n \ge 1$, the sum of distributed column widths exactly equals $W_{\text{avail}}$:
    $$W_{\text{avail}} \ge \sum_{i=1}^n m_i \implies \sum_{i=1}^n W_i(W_{\text{avail}}) = W_{\text{avail}}$$
    Conversely, if $W_{\text{avail}} < \sum_{i=1}^n m_i$, then $\sum_{i=1}^n W_i(W_{\text{avail}}) = \sum_{i=1}^n m_i$ (the table overflows $W_{\text{avail}}$). Together:
    $$\sum_{i=1}^n W_i(W_{\text{avail}}) = \max\left(W_{\text{avail}}, \sum_{i=1}^n m_i\right)$$

3.  **Monotonicity with Respect to Available Inline Size:**
    Increasing the assignable inline size of the table never causes any individual column to shrink:
    $$\forall W_1, W_2 \ge 0,\quad W_1 \le W_2 \implies \forall i \in \{1, \dots, n\},\quad W_i(W_1) \le W_i(W_2)$$

---

### 5. Rocq / Coq Formalization (`BlinkTableColumnDistributionSemantics.v`)

The following complete, self-contained Rocq (Coq) development formalizes Blink's column structures, the 4-stage piecewise linear guess interpolation for `auto` layout, the `fixed` layout distributor, and proves the core mathematical invariants over exact rational arithmetic (`Q`).

```coq
(** * BlinkTableColumnDistributionSemantics.v
    Formalization of Chromium Blink LayoutNG Table Column Width Distribution
    vs. CSS 2.1 §17.5.2 & CSS Table Module Level 3. *)

From Coq Require Import List QArith Qminmax Lia Lra Bool.
Import ListNotations.
Open Scope Q_scope.

(** ** 1. Core Data Structures *)

Inductive ColumnKind : Type :=
  | ColAuto       (* Unconstrained column *)
  | ColFixed      (* Constrained by fixed <length> *)
  | ColPercent    (* Constrained by <percentage> *).

Record ColumnConstraint : Type := mkColumn {
  col_min : Q;           (* min_inline_size