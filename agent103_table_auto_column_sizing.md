## 1. Core Data Structures in Blink Column Sizing

In Chromium's Blink layout engine (`third_party/blink/renderer/core/layout/table/`), automatic table layout column sizing is governed by the definitions in `table_layout_algorithm_types.h` and `table_layout_algorithm_helpers.cc`. These structures translate CSS 2.1 §17.5.2.2 and the CSS Table Module Level 3 draft into fixed-point arithmetic (`LayoutUnit`).

### `MinMaxSizes`
Represents the intrinsic minimum and maximum content sizes of a layout box:
```cpp
struct MinMaxSizes {
  LayoutUnit min_size; // Minimum content size (e.g., longest unbreakable word)
  LayoutUnit max_size; // Maximum content size (e.g., content without line wrapping)
};
```

### `TableTypes::CellInlineConstraint`
Captures the inline sizing contributions of a single table cell (`<td>` or `<th>`):
```cpp
struct CellInlineConstraint {
  LayoutUnit min_size;
  LayoutUnit max_size;
  std::optional<float> percent; // Percentage width if specified (e.g., width: 50%)
  LayoutUnit percent_border_padding; // Border + padding to add to resolved percentage
  bool is_constrained; // True if the cell has an explicit specified width (px or %)
};
```

### `TableTypes::Column`
Represents the aggregated sizing constraints of a single grid column, synthesized from `<col>` elements and the cells spanning that column:
```cpp
struct Column {
  LayoutUnit min_inline_size;
  LayoutUnit max_inline_size;
  std::optional<float> percent;
  LayoutUnit percent_border_padding;
  bool is_constrained = false;
  bool is_collapsed = false;
  bool is_table_fixed = false;
  bool is_mergeable = false;

  // Resolves the effective minimum inline size considering percentage constraints
  // against the total table inline size.
  LayoutUnit ResolvePercentInlineSize(LayoutUnit percentage_resolution_inline_size) const;
};
```
Blink partitions columns into distinct structural categories during distribution:
1. **Auto (Unconstrained)**: `is_constrained == false && !percent.has_value()`
2. **Fixed (Constrained)**: `is_constrained == true && !percent.has_value()`
3. **Percent**: `percent.has_value()`
4. **Empty**: `min_inline_size == 0 && max_inline_size == 0`

---

## 2. Column Min/Max Derivation

Let $C$ be the set of columns Indexed by $i \in \{0, \dots, n-1\}$.

### Step 2.1: Initialization from `<col>` Elements
For each column $i$, let $Col_i$ be the constraint derived from the corresponding `<col>` or `<colgroup>` element:
$$\text{min}_i^{(0)} = Col_i.\text{min\_size}, \quad \text{max}_i^{(0)} = Col_i.\text{max\_size}$$

### Step 2.2: Aggregation of Non-Spanning Cells ($\text{colspan} = 1$)
Let $\mathcal{K}_i^{(1)}$ be the set of cells positioned at column $i$ with $\text{colspan} = 1$. In accordance with CSS 2.1 §17.5.2.2, the column's intrinsic boundaries are the upper bounds of its constituent cells' intrinsic boundaries, coupled with cross-clamping for fixed-width constraints:

$$\text{min}_i^{(1)} = \max \left( \text{min}_i^{(0)}, \max_{c \in \mathcal{K}_i^{(1)}} c.\text{min\_size} \right)$$

$$\text{max}_i^{(1)} = \max \left( \text{max}_i^{(0)}, \max_{c \in \mathcal{K}_i^{(1)}} c.\text{max\_size} \right)$$

**Blink Enforcement Invariant**: If a column is marked constrained by a `<col>` element with a fixed width $W_{\text{col}}$, its maximum size is initially clamped, but a cell's minimum content size always overrides a fixed maximum size:
$$\text{max}_i^{(1)} = \max\left(\text{min}_i^{(1)}, \text{max}_i^{(1)}\right)$$

### Step 2.3: Distribution of Spanning Cells ($\text{colspan} > 1$)
For a cell $c$ spanning columns $S = \{s, s+1, \dots, s+k-1\}$ with border-spacing $\Delta$:
Let the baseline column aggregates be $M_{\min}(S) = \sum_{j \in S} \text{min}_j^{(1)} + (k-1)\Delta$ and $M_{\max}(S) = \sum_{j \in S} \text{max}_j^{(1)} + (k-1)\Delta$.
If $c.\text{min\_size} > M_{\min}(S)$, the excess minimum size $E_{\min} = c.\text{min\_size} - M_{\min}(S)$ is distributed across the spanned columns $j \in S$ using the same priority rules as table width distribution (Section 3), updating $\text{min}_j$. The same holds for $E_{\max} = \max(0, c.\text{max\_size} - M_{\max}(S))$.

---

## 3. Distributing Available Table Width Across Columns

Let $W_{\text{avail}}$ be the assignable table inline size (total table inline size minus outer borders, table padding, and $(n+1) \cdot \text{border-spacing}$).

For each column $i \in \{0, \dots, n-1\}$, let:
- $m_i = \text{min\_inline\_size}_i$
- $M_i = \max(m_i, \text{max\_inline\_size}_i)$
- $p_i \in [0, 100]$ be the clamped percentage (such that $\sum p_i \le 100$).

Define the effective minimum and maximum sizes at target width $W_{\text{avail}}$:
$$\tilde{m}_i(W_{\text{avail}}) = m_i$$
$$\tilde{M}_i(W_{\text{avail}}) = \begin{cases} 
\max\left(m_i, \frac{p_i}{100} W_{\text{avail}} + \text{pbp}_i\right) & \text{if } p_i > 0 \\
M_i & \text{if } p_i = 0 
\end{cases}$$

Let $M_{\text{sum}} = \sum_{i=0}^{n-1} m_i$ and $\tilde{M}_{\text{sum}} = \sum_{i=0}^{n-1} \tilde{M}_i(W_{\text{avail}})$.

### Case A: Constrained Deficit ($W_{\text{avail}} \le M_{\text{sum}}$)
The assignable table width cannot satisfy the minimum intrinsic widths of the columns. Every column is assigned its absolute minimum width:
$$\forall i, \quad w_i = m_i$$

### Case B: Intermediate / Excess Growth ($M_{\text{sum}} < W_{\text{avail}} \le \tilde{M}_{\text{sum}}$)
Let the excess space be $\Delta W = W_{\text{avail}} - M_{\text{sum}}$, and let the growth capacity (headroom) of column $i$ be $d_i = \tilde{M}_i(W_{\text{avail}}) - m_i$. Since $W_{\text{avail}} \le \tilde{M}_{\text{sum}}$, we have $\sum_{i=0}^{n-1} d_i = D \ge \Delta W > 0$.

Each column expands from its minimum size proportionally to its share of the total growth capacity:
$$\forall i, \quad w_i = m_i + \Delta W \cdot \frac{d_i}{\sum_{j=0}^{n-1} d_j}$$

*(Note: In Blink's `SynchronizeAssignableTableInlineSizeAndColumns`, this intermediate growth is staged across priorities: first satisfying unconstrained auto columns up to their max, then fixed columns, then percent columns).*

### Case C: Unbounded Excess ($W_{\text{avail}} > \tilde{M}_{\text{sum}}$)
First, all columns are promoted to their effective maximum sizes: $w_i^{\text{base}} = \tilde{M}_i(W_{\text{avail}})$.
The remaining surplus $\Delta W_{\text{rem}} = W_{\text{avail}} - \tilde{M}_{\text{sum}}$ is distributed according to Blink's strict priority hierarchy (`DistributeAvailableInlineSizeToCols`). Let the column index sets be:
1. $G_1 = \{i \mid \text{Auto} \land M_i > 0\}$ (Non-empty unconstrained columns; weights $\omega_i = M_i$)
2. $G_2 = \{i \mid \text{Fixed} \land M_i > 0\}$ (Non-empty fixed columns; weights $\omega_i = M_i$)
3. $G_3 = \{i \mid \text{Percent} \land p_i > 0\}$ (Percent columns; weights $\omega_i = p_i$)
4. $G_4 = \{i \mid M_i = 0\}$ (Empty columns; uniform weights $\omega_i = 1$)

Let $k = \min \{r \in \{1, 2, 3, 4\} \mid G_r \neq \emptyset\}$. For all $i$:
$$w_i = \tilde{M}_i(W_{\text{avail}}) + \begin{cases} 
\Delta W_{\text{rem}} \cdot \frac{\omega_i}{\sum_{j \in G_k} \omega_j} & \text{if } i \in G_k \\
0 & \text{if } i \notin G_k 
\end{cases}$$

---

## 4. Mathematical Invariants

For any valid column configuration $C = \{(m_i, M_i)\}_{i=0}^{n-1}$ where $0 \le m_i \le M_i$ and available width $W \ge 0$, the distribution function $f_i(C, W) = w_i$ satisfies the following core layout invariants:

1. **Lower Bound Preservation (Safety)**: No column is ever sized narrower than its intrinsic minimum content width.
   $$\forall i, \quad w_i \ge m_i$$

2. **Exact Space Conservation (Completeness)**: If $n > 0$, the sum of distributed column widths equals the maximum of the available table width and the sum of column minimums.
   $$\sum_{i=0}^{n-1} w_i = \max\left(W, \sum_{i=0}^{n-1} m_i\right)$$

3. **Bounded Intermediate Growth**: Whenever available width does not exceed the sum of maximums ($W \le \sum M_i$), no column exceeds its maximum intrinsic size.
   $$W \le \sum_{i=0}^{n-1} M_i \implies \forall i, \quad m_i \le w_i \le M_i$$

4. **Monotonicity with respect to Available Width**: Increasing the available table width never decreases the allocated width of any individual column.
   $$W_1 \le W_2 \implies \forall i, \quad f_i(C, W_1) \le f_i(C, W_2)$$

---

## 5. Concrete Rocq/Coq Formalization (`BlinkTableAutoColumnSizingSemantics.v`)

The following script is a self-contained, vernacular-valid Coq (Rocq) development using rational arithmetic (`QArith` / `Lra`) to formalize the exact mathematical semantics of column derivation and proportional distribution, complete with closed-form proofs of the invariants.

```coq
(** * BlinkTableAutoColumnSizingSemantics.v
    Formalization of Chromium Blink Table Auto Column Sizing vs CSS 2.1 §17.5.2.2
    Agent 103 Audit Artifact *)

From Coq Require Import List.
From Coq Require Import QArith.
From Coq Require Import Qminmax.
From Coq Require Import Lra.
Import ListNotations.

Open Scope Q_scope.

(** ** 1. Core Data Structures *)

Record CellConstraint := mkCell {
  cell_min : Q;
  cell_max : Q;
  cell_wf  : 0 <= cell_min /\ cell_min <= cell_max
}.

Inductive ColumnType :=
  | ColAuto
  | ColFixed
  | ColPercent (pct : Q).

Record Column := mkColumn {
  col_min  : Q;
  col_max  : Q;
  col_type : ColumnType;
  col_wf   : 0 <= col_min /\ col_min <= col_max
}.

(** ** 2. Column Min/Max Derivation from Cells *)

Definition max_Q (a b : Q) : Q :=
  if Qlt_le_dec a b then b else a.

Lemma max_Q_ge_l : forall a b, a <= max_Q a b.
Proof.
  intros a b; unfold max_Q; destruct (Qlt_le_dec a b); lra.
Qed.

Lemma max_Q_ge_r : forall a b, b <= max_Q a b.
Proof.
  intros a b; unfold max_Q; destruct (Qlt_le_dec a b); lra.
Qed.

Lemma max_Q_lub : forall a b c, a <= c -> b <= c -> max_Q a b <= c.
Proof.
  intros a b c Ha Hb; unfold max_Q; destruct (Qlt_le_dec a b); lra.
Qed.

Fixpoint derive_col_min (cells : list CellConstraint) : Q :=
  match cells with
  | [] => 0
  | c :: cs => max_Q (cell_min c) (derive_col_min cs)
  end.

Fixpoint derive_col_max (cells : list CellConstraint) : Q :=
  match cells with
  | [] => 0
  | c :: cs => max_Q (cell_max c) (derive_col_max cs)
  end.

Theorem derive_min_nonneg : forall cells, 0 <= derive_col_min cells.
Proof.
  induction cells as [|c cs IH]; simpl.
  - lra.
  - pose proof (cell_wf c) as [H0 _].
    pose proof (max_Q_ge_r (cell_min c) (derive_col_min cs)).
    lra.
Qed.

Theorem derive_min_le_max : forall cells,
  derive_col_min cells <= derive_col_max cells.
Proof.
  induction cells as [|c cs IH]; simpl.
  - lra.
  - apply max_Q_lub.
    + pose proof (cell_wf c) as [_ Hle].
      pose proof (max_Q_ge_l (cell_max c) (derive_col_max cs)).
      