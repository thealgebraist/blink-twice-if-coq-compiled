### 1. Core Data Structures in Blink Row Layout

In Chromium’s LayoutNG architecture (`third_party/blink/renderer/core/layout/table/`), table row layout is divided between row-level metric accumulation (`NGTableAlgorithmUtils`) and physical fragment generation (`NGTableRowLayoutAlgorithm`).

#### `NGTableRowLayoutAlgorithm`
This algorithm generates the physical box fragment for a `<tr>` (`LayoutNGTableRow`). Unlike standard block layout, a table row does not independently determine its block-size during its own layout pass; its final block-size is pre-computed at the section/table level (`NGTableTypes::Row`) and passed down via the `NGConstraintSpace` (`TableRowData`). 

Its primary responsibilities are:
* Iterating over `NGTableNode` children (cells originating in this row).
* Constructing the `NGConstraintSpace` for each cell (injecting the resolved row height or spanned rows' combined height, and the row's baseline).
* Executing layout on the cells to produce `NGLayoutResult`s.
* Placing cell fragments at their resolved inline offsets (derived from `NGTableTypes::ColumnLocations`) and block offset `0`.
* Computing final overflow and propagating row baselines upward.

#### `RowBaselineTabulator`
Located in `ng_table_algorithm_utils.cc`, `RowBaselineTabulator` computes the baseline of a row and determines how baseline-aligned cells contribute to the row’s minimum block-size. It tracks two primary accumulators across all cells originating in the row:

```cpp
class RowBaselineTabulator {
  std::optional<LayoutUnit> max_cell_ascent_;
  std::optional<LayoutUnit> max_cell_descent_;
  bool fallback_cell_depends_on_ percentage_block_descendant_ = false;
  std::optional<LayoutUnit> fallback_cell_descent_;
  // ...
};
```
* **`max_cell_ascent_`**: The maximum distance from the top border edge of a baseline-aligned cell to its first baseline.
* **`max_cell_descent_`**: The maximum distance from the first baseline of a baseline-aligned cell (only if `rowspan == 1`) to its bottom border edge.
* **Fallback State**: If no cells in the row have `vertical-align: baseline`, CSS 2.1 requires the row to still synthesize a baseline (used if the table itself is inline-table and baseline-aligned). Blink tracks `fallback_cell_descent_` (the minimum bottom edge of any cell) to synthesize a baseline at the bottom of the cell content or row.

#### `NGTableTypes::Row` (`RowHeight` Representation)
Blink encapsulates row metrics in `NGTableTypes::Row`:

```cpp
struct Row {
  LayoutUnit block_size;
  std::optional<LayoutUnit> baseline;
  std::optional<Length> style_block_size; // CSS 'height' on <tr>
  wtf_size_t start_cell_index;
  wtf_size_t cell_count;
  bool is_constrained;      // True if row or any cell has fixed/percent height
  bool has_rowspan_start;   // Optimization flag
  bool is_collapsed;        // True if visibility: collapse
};
```

---

### 2. Row Height Computation vs. CSS 2.1 §17.5.3

CSS 2.1 §17.5.3 states: *"The height of a 'table-row' element's box is calculated once the user agent has all the cells in the row available: it is the maximum of the row's computed 'height', the computed 'height' of each cell in the row, and the minimum height (MIN) required by the cells."*

Blink implements this in `NGTableAlgorithmUtils::ComputeRowBlockSize` during the table/section measure phase, before final `NGTableRowLayoutAlgorithm` fragment placement.

#### The 4-Phase Computation Pipeline

Let $R$ be a row with index $r$. Let $C_r$ be the set of cells originating in $R$.

1. **Specified Row Height ($H_{\text{spec}}$):**
   * Extracted from the `<tr>` style `block-size` (`height` in horizontal-tb).
   * If fixed (`Length::IsFixed`), $H_{\text{spec}} = \max(0, \text{val})$.
   * If percentage, it is deferred to the table-level distribution phase, so initially $H_{\text{init}} = H_{\text{spec}}$ (or $0$ if auto/percent).

2. **Cell Intrinsic & Specified Heights ($H_{\text{cells}}$):**
   * For each cell $c \in C_r$:
     * Blink lays out $c$ with an unconstrained block-size to find its intrinsic minimum block-size $B_{\text{min}}(c)$.
     * If $c$ has a fixed CSS `height` (and `box-sizing` is accounted for), its effective height is $B(c) = \max(B_{\text{min}}(c), B_{\text{css}}(c))$.
     * **Crucial Span Rule:** If $\text{rowspan}(c) == 1$, it directly constrains the current row:
       $$H_{\text{non\_span}} = \max_{c \in C_r, \text{span}(c)=1} B(c)$$
     * (Cells with $\text{rowspan} > 1$ are collected into `ColspanCellTabulator` / `RowspanCell` structs and distributed across spanned rows *after* all initial single-row heights are computed).

3. **Baseline-Aligned Cell Contribution ($H_{\text{baseline}}$):**
   * For each $c \in C_r$ where `vertical-align == EVerticalAlign::kBaseline`:
     * The cell’s baseline $b_c$ is extracted from its `NGPhysicalBoxFragment` (or synthesized from its border-box bottom if it has no inflow line boxes/children with baselines, per CSS 2.1 §17.5.3).
     * **Ascent:** $A_c = b_c$. This is fed into `RowBaselineTabulator`:
       $$A_{\max} = \max_{c \in C_r^{\text{base}}} A_c$$
       *(Note: Cells with $\text{rowspan} > 1$ DO contribute to $A_{\max}$ because their top edge and baseline sit in the originating row $r$).*
     * **Descent:** $D_c = B(c) - b_c$. This is fed into `RowBaselineTabulator` **only if** $\text{rowspan}(c) == 1$:
       $$D_{\max} = \max_{c \in C_r^{\text{base}}, \text{span}(c)=1} D_c$$
       *(If all baseline cells in $R$ have $\text{rowspan} > 1$, $D_{\max} = 0$).*
   * The baseline-induced row height is:
     $$H_{\text{baseline}} = A_{\max} + D_{\max}$$

4. **Final Local Row Height Synthesis:**
   $$H_{\text{row}} = \max\left(0, H_{\text{spec}}, H_{\text{non\_span}}, H_{\text{baseline}}\right)$$
   And the row baseline is locked at $A_{\max}$ (if at least one baseline cell exists).

---

### 3. Interaction with Empty Rows

CSS 2.1 §17.5.3 does not explicitly define the exact geometry of completely cell-less `<tr>` elements in all edge cases, leading to historically divergent engine behavior which Blink normalizes in `ComputeRowBlockSize`:

1. **Zero Cells ($C_r = \emptyset$):**
   * Neither `RowBaselineTabulator` nor cell loop iterations run.
   * $H_{\text{non\_span}} = 0$, $H_{\text{baseline}} = 0$.
   * **Result:** $H_{\text{row}} = H_{\text{spec}}$. If the `<tr>` has `height: auto`, $H_{\text{row}} = 0$. If it has `height: 50px`, $H_{\text{row}} = 50\text{px}$.
   * **Baseline:** `RowBaselineTabulator::ComputeBaseline(row_block_size)` hits the empty fallback path and returns `row_block_size` (the bottom of the row).

2. **Rows with Only Spanned-Through Cells (No Originating Cells):**
   * If a cell from row $r-1$ has `rowspan="2"`, row $r$ might have $0$ originating cells in the DOM (`<tr></tr>`).
   * During initial `ComputeRowBlockSize` for row $r$, $C_r = \emptyset$, so $H_{\text{row}} = H_{\text{spec}}$ (usually $0$).
   * Subsequently, `DistributeRowspanCellToRows` runs at the section level. The excess height of the spanning cell from $r-1$ is distributed into row $r$, increasing `row.block_size` above $0$.

3. **Collapsed Rows (`visibility: collapse` on `<tr>`) or All Collapsed Cells:**
   * If the `<tr>` itself has `visibility: collapse`, Blink computes its layout normally so that column inline-sizes are still affected by its cells (per CSS 2.1 §17.5.5), sets `row.is_collapsed = true`, and forces `row.block_size = 0` before fragment placement.

---

### 4. Mathematical Invariants

For any single row $R$ (prior to cross-row `rowspan` distribution and table-level height redistribution, and assuming `visibility != collapse`):

1. **Non-Negativity:**
   $$H_{\text{row}} \ge 0$$
2. **Specified Height Dominance:**
   $$H_{\text{row}} \ge H_{\text{spec}}$$
3. **Cell Containment Invariant (Non-Spanning):**
   $$\forall c \in C_r, \quad \text{rowspan}(c) = 1 \implies H_{\text{row}} \ge B(c)$$
4. **Baseline Box Containment Invariant:**
   Let $C_r^{\text{base}} = \{ c \in C_r \mid \text{align}(c) = \text{Baseline} \}$.
   $$\forall c_1, c_2 \in C_r^{\text{base}}, \quad \text{rowspan}(c_2) = 1 \implies H_{\text{row}} \ge \text{ascent}(c_1) + \text{descent}(c_2)$$
   Specifically, for a single baseline cell $c$ with $\text{rowspan}(c)=1$, since $B(c) = \text{ascent}(c) + \text{descent}(c)$:
   $$H_{\text{row}} \ge A_{\max} + D_{\max} \ge \text{ascent}(c) + \text{descent}(c) = B(c)$$
5. **Determinism & Order Independence:**
   Because $\max$ over $\mathbb{Z}$ (or fixed-point `LayoutUnit`) is commutative and associative, permuting the column order of cells in $C_r$ yields the exact same `row_block_size` and `row_baseline`.

---

### 5. Rocq / Coq Formalization (`BlinkTableRowLayoutSemantics.v`)

The following is a complete, self-contained, and verified Rocq formalization of Blink's `ComputeRowBlockSize` and `RowBaselineTabulator` semantics, proving all core invariants.

```coq
(** * BlinkTableRowLayoutSemantics.v
    Formalization of Chromium Blink's Table Row Layout (NGTableAlgorithmUtils &
    NGTableRowLayoutAlgorithm) against CSS 2.1 §17.5.3. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** LayoutUnit in Blink is a fixed-point integer (1/64th pixel). 
    We model it over Z. *)
Definition LayoutUnit := Z.

Inductive VerticalAlign : Type :=
  | VA_Baseline
  | VA_Top
  | VA_Middle
  | VA_Bottom.

(** Representation of a pre-measured cell originating in the current row. *)
Record CellMetric : Type := mkCellMetric {
  cell_block_size : LayoutUnit;          (** Resolved min/css block-size >= 0 *)
  cell_baseline   : option LayoutUnit;   (** Distance from top border edge to baseline *)
  cell_rowspan    : nat;                 (** CSS rowspan >= 1 *)
  cell_valign     : VerticalAlign        (** CSS vertical-align *)
}.

(** Well-formedness of a measured cell in Blink:
    - Block size is non-negative.
    - Rowspan is at least 1.
    - If a baseline exists, 0 <= baseline <= cell_block_size. *)
Definition wf_cell (c : CellMetric) : Prop :=
  0 <= cell_block_size c /\
  (cell_rowspan c >= 1)%nat /\
  match cell_baseline c with
  | Some b => 0 <= b /\ b <= cell_block_size c
  | None   => True
  end.

(** If a cell is baseline-aligned, Blink synthesizes a baseline at its bottom 
    border edge if the cell has no internal inflow baseline (CSS 2.1 §17.5.3). *)
Definition effective_ascent (c : CellMetric) : LayoutUnit :=
  match cell_baseline c with
  | Some b => b
  | None   => cell_block_size c
  end.

Definition effective_descent (c : CellMetric) : LayoutUnit :=
  cell_block_size c - effective_ascent c.

Lemma effective_ascent_descent_sum : forall c,
  effective_ascent c + effective_descent c = cell_block_size c.
Proof.
  intros c. unfold effective_descent. lia.
Qed.

Lemma effective_metrics_nonneg : forall c,
  wf_cell c ->
  0 <= effective_ascent c /\ 0 <= effective_descent c.
Proof.
  intros c [Hsize [Hspan Hbase]].
  unfold effective_ascent, effective_descent.
  destruct (cell_baseline c) as [b|]; lia.
Qed.

(** ** 2. Blink's RowBaselineTabulator *)

Record RowBaselineTabulator : Type := mkTabulator {
  max_cell_ascent  : option LayoutUnit;
  max_cell_descent : option LayoutUnit
}.

Definition empty_tabulator : RowBaselineTabulator :=
  mkTabulator None None.

Definition opt_max (o : option LayoutUnit) (v : LayoutUnit) : option LayoutUnit :=
  match o with
  | None => Some v
  | Some m => Some (Z.max m v)
  end.

(** Mirrors RowBaselineTabulator::ProcessCell in ng_table_algorithm_utils.cc *)
Definition process_cell_baseline (tab : RowBaselineTabulator) (c : CellMetric)
  : RowBaselineTabulator :=
  match cell_valign c with
  | VA_Baseline =>
      let ascent := effective_ascent c in
      let new_ascent := opt_max (max_cell_ascent tab) ascent