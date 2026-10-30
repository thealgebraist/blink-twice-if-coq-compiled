### 1. Core Data Structures in Blink Table Row Layout

In Chromium’s Blink LayoutNG architecture (`third_party/blink/renderer/core/layout/table/`), table row baseline alignment and height resolution are governed by the interaction between the row layout algorithm, cell layout fragments, and grid-level metric aggregators.

#### `TableRowLayoutAlgorithm`
Inherits from `LayoutAlgorithm<TableRowNode, BoxFragmentBuilder, TableRowBreakToken>`. It is responsible for positioning cells along the inline axis and computing the row's block-size and baseline metrics when fragmenting or executing standard block layout. In monolithic table grid passes, row baseline calculation is also mirrored in `TableLayoutUtils::ComputeRowBaseline`.

#### `TableRowMetrics` (Internal Grid/Row Representation)
Aggregates the resolved block-size and baseline offsets for a specific row:
*   `LayoutUnit block_size`: The final computed height of the row ($H_{\text{row}}$).
*   `std::optional<LayoutUnit> baseline`: The distance from the row’s block-start edge to the shared row baseline.
*   `bool has_baseline_aligned_cells`: Flag indicating if any cell in the row has `vertical-align: baseline`.

#### `CellBaselineInfo` (Extracted per `BlockNode` / `PhysicalBoxFragment`)
For each cell $c$ spanning exclusively a single row (or starting at the current row, depending on baseline propagation rules):
*   `LayoutUnit border_box_block_size`: Total computed height of the cell's border box ($H_{\text{content}}(c)$), incorporating `border-top + padding-top + content_block_size + padding-bottom + border-bottom`.
*   `std::optional<LayoutUnit> first_baseline`: Extracted from `LogicalBoxFragment::FirstBaseline()`. If the cell is baseline-aligned (`vertical-align: baseline`) and possesses an in-flow line box, block-level flex/grid baseline, or table baseline, this holds the offset from the cell's border-box top edge to that baseline. If no natural baseline exists, Blink synthesizes it at the bottom of the content box (or border box per CSS 2.1 §17.5.3).
*   ` EVerticalAlign vertical_align`: The computed `vertical-align` property (`kBaseline`, `kTop`, `kMiddle`, `kBottom`).

---

### 2. Baseline Aggregation Algorithm

Per **CSS 2.1 §17.5.3 (Table height algorithms)**, the baseline of a row is the maximum distance between the top of the cell box and the baseline over all cells that have `vertical-align: baseline`.

Let $\mathcal{C}$ be the set of cells originating in the row with $\text{rowspan} = 1$. Let $\mathcal{C}_{\text{base}} \subseteq \mathcal{C}$ be the subset of cells where `vertical-align == baseline`.

For each cell $c \in \mathcal{C}$:
1.  **Content Height**: $H_{\text{content}}(c) \ge 0$.
2.  **Ascent ($A(c)$)**: If $c \in \mathcal{C}_{\text{base}}$, $A(c)$ is the cell's resolved baseline offset from its top border edge ($0 \le A(c) \le H_{\text{content}}(c)$).
3.  **Descent ($D(c)$)**: If $c \in \mathcal{C}_{\text{base}}$, the descent is the remaining block-size below the baseline:
    $$D(c) = H_{\text{content}}(c) - A(c)$$

The row-level baseline metrics are aggregated by iterating over $\mathcal{C}_{\text{base}}$:
$$\text{max\_ascent} = \max_{c \in \mathcal{C}_{\text{base}}} \{ A(c) \} \quad (\text{defaults to } 0 \text{ if } \mathcal{C}_{\text{base}} = \emptyset)$$
$$\text{max\_descent} = \max_{c \in \mathcal{C}_{\text{base}}} \{ D(c) \} \quad (\text{defaults to } 0 \text{ if } \mathcal{C}_{\text{base}} = \emptyset)$$

The row's baseline offset $B_{\text{row}}$ from the row's top edge is fixed at $\text{max\_ascent}$ (unless adjusted by legacy quirks when $\mathcal{C}_{\text{base}} = \emptyset$).

---

### 3. Final Row Height Resolution

Once $\text{max\_ascent}$ and $\text{max\_descent}$ are established, any baseline-aligned cell $c \in \mathcal{C}_{\text{base}}$ is shifted downward by $\Delta y(c) = \text{max\_ascent} - A(c)$ so its baseline aligns with $B_{\text{row}}$. The total vertical span required to house all baseline-aligned cells is therefore $\text{max\_ascent} + \text{max\_descent}$.

Non-baseline-aligned cells ($c \notin \mathcal{C}_{\text{base}}$, e.g., `top`, `middle`, `bottom`) do not contribute to $\text{max\_ascent}$ or $\text{max\_descent}$, but their border-box height $H_{\text{content}}(c)$ still constrains the minimum height of the row.

Finally, the row itself may have an author-specified computed block-size $H_{\text{spec}}$ (from the `<tr>` CSS `height` property).

The final row height $H_{\text{row}}$ is resolved as:
$$H_{\text{row}} = \max \left( H_{\text{spec}}, \; \text{max\_ascent} + \text{max\_descent}, \; \max_{c \in \mathcal{C}} H_{\text{content}}(c) \right)$$

---

### 4. Mathematical Invariants

1.  **Baseline Span Containment**:
    $$H_{\text{row}} \ge \text{max\_ascent} + \text{max\_descent}$$
2.  **Specified Height Monotonicity**:
    $$H_{\text{row}} \ge H_{\text{spec}}$$
3.  **Universal Cell Content Containment**:
    For every cell $c \in \mathcal{C}$, its positioned vertical interval $[y_{\text{top}}(c), y_{\text{bottom}}(c)]$ within the row satisfies $0 \le y_{\text{top}}(c)$ and $y_{\text{bottom}}(c) \le H_{\text{row}}$, which implies:
    $$\forall c \in \mathcal{C}, \quad H_{\text{row}} \ge H_{\text{content}}(c)$$
    Furthermore, for $c \in \mathcal{C}_{\text{base}}$, since $y_{\text{top}}(c) = \text{max\_ascent} - A(c)$ and $y_{\text{bottom}}(c) = y_{\text{top}}(c) + H_{\text{content}}(c) = \text{max\_ascent} + D(c) \le \text{max\_ascent} + \text{max\_descent} \le H_{\text{row}}$, no baseline-aligned cell overflows the row box.
4.  **Determinism & Order Independence**:
    Because $\max$ over finite sets in $\mathbb{N}$ (or fixed-point `LayoutUnit`) is associative, commutative, and idempotent, the computed metrics $(H_{\text{row}}, \text{max\_ascent}, \text{max\_descent})$ are deterministic and invariant under permutation of cell order.

---

### 5. Formalization in Rocq / Coq (`BlinkTableRowBaselineSemantics.v`)

The following complete, self-contained Rocq (Coq) script formalizes the data structures, aggregation functions, and proofs of all four mathematical invariants.

```coq
(** * BlinkTableRowBaselineSemantics.v
    Formal verification of Chromium Blink Table Row Baseline Alignment
    against CSS 2.1 Section 17.5.3. *)

From Coq Require Import Arith PeanoNat List Bool Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

Inductive VerticalAlign : Type :=
  | VA_Baseline
  | VA_Top
  | VA_Middle
  | VA_Bottom.

(** Represents a single-row table cell's layout metrics.
    In Blink LayoutNG, heights and baselines are represented in fixed-point
    LayoutUnits (modeled here as natural numbers in subpixel units). *)
Record CellBaselineInfo : Type := mkCell {
  cell_content_height : nat;
  cell_baseline_offset : nat; (* Valid/used when vertical_align = VA_Baseline *)
  cell_valign : VerticalAlign;
}.

(** Well-formedness predicate for a cell:
    A cell's internal baseline cannot exceed its own border-box content height. *)
Definition wf_cell (c : CellBaselineInfo) : Prop :=
  cell_baseline_offset c <= cell_content_height c.

Record TableRowMetrics : Type := mkRowMetrics {
  row_max_ascent : nat;
  row_max_descent : nat;
  row_block_size : nat;
}.

(** ** 2. Baseline & Height Aggregation Algorithm *)

Definition is_baseline_aligned (c : CellBaselineInfo) : bool :=
  match cell_valign c with
  | VA_Baseline => true
  | _ => false
  end.

Definition cell_ascent (c : CellBaselineInfo) : nat :=
  if is_baseline_aligned c then cell_baseline_offset c else 0.

Definition cell_descent (c : CellBaselineInfo) : nat :=
  if is_baseline_aligned c then (cell_content_height c - cell_baseline_offset c) else 0.

Fixpoint compute_max_ascent (cells : list CellBaselineInfo) : nat :=
  match cells with
  | [] => 0
  | c :: rest => Nat.max (cell_ascent c) (compute_max_ascent rest)
  end.

Fixpoint compute_max_descent (cells : list CellBaselineInfo) : nat :=
  match cells with
  | [] => 0
  | c :: rest => Nat.max (cell_descent c) (compute_max_descent rest)
  end.

Fixpoint compute_max_content_height (cells : list CellBaselineInfo) : nat :=
  match cells with
  | [] => 0
  | c :: rest => Nat.max (cell_content_height c) (compute_max_content_height rest)
  end.

(** Final row height formula:
    H_row = max(specified_height, max_ascent + max_descent, max_c content_height(c)) *)
Definition compute_row_height (specified_height : nat) (cells : list CellBaselineInfo) : nat :=
  let max_a := compute_max_ascent cells in
  let max_d := compute_max_descent cells in
  let max_c := compute_max_content_height cells in
  Nat.max specified_height (Nat.max (max_a + max_d) max_c).

Definition layout_table_row (specified_height : nat) (cells : list CellBaselineInfo) : TableRowMetrics :=
  mkRowMetrics
    (compute_max_ascent cells)
    (compute_max_descent cells)
    (compute_row_height specified_height cells).

(** Cell block-start offset (y_top) inside the row after alignment *)
Definition cell_y_offset (row : TableRowMetrics) (c : CellBaselineInfo) : nat :=
  match cell_valign c with
  | VA_Baseline => row_max_ascent row - cell_ascent c
  | VA_Top      => 0
  | VA_Middle   => (row_block_size row - cell_content_height c) / 2
  | VA_Bottom   => row_block_size row - cell_content_height c
  end.

(** ** 3. Lemmas for List Aggregations *)

Lemma in_max_ascent : forall (cells : list CellBaselineInfo) (c : CellBaselineInfo),
  In c cells -> cell_ascent c <= compute_max_ascent cells.
Proof.
  induction cells as [| x rest IH]; intros c HIn; simpl in *.
  - contradiction.
  - destruct HIn as [Heq | HIn].
    + subst. lia.
    + specialize (IH c HIn). lia.
Qed.

Lemma in_max_descent : forall (cells : list CellBaselineInfo) (c : CellBaselineInfo),
  In c cells -> cell_descent c <= compute_max_descent cells.
Proof.
  induction cells as [| x rest IH]; intros c HIn; simpl in *.
  - contradiction.
  - destruct HIn as [Heq | HIn].
    + subst. lia.
    + specialize (IH c HIn). lia.
Qed.

Lemma in_max_content_height : forall (cells : list CellBaselineInfo) (c : CellBaselineInfo),
  In c cells -> cell_content_height c <= compute_max_content_height cells.
Proof.
  induction cells as [| x rest IH]; intros c HIn; simpl in *.
  - contradiction.
  - destruct HIn as [Heq | HIn].
    + subst. lia.
    + specialize (IH c HIn). lia.
Qed.

(** ** 4. Formal Verification of Mathematical Invariants *)

(** Invariant 1: H_row >= max_ascent + max_descent *)
Theorem row_height_ge_baseline_span :
  forall (spec_h : nat) (cells : list CellBaselineInfo),
    let m := layout_table_row spec_h cells in
    row_block_size m >= row_max_ascent m + row_max_descent m.
Proof.
  intros spec_h cells m.
  unfold m, layout_table_row, compute_row_height; simpl.
  lia.
Qed.

(** Invariant 2: H_row >= specified_height *)
Theorem row_height_ge_specified_height :
  forall (spec_h : nat) (cells : list CellBaselineInfo),
    let m := layout_table_row spec_h cells in
    row_block_size m >= spec_h.
Proof.
  intros spec_h cells m.
  unfold m, layout_table_row, compute_row_height; simpl.
  lia.
Qed.

(** Invariant 3a: Every cell's content height is bounded by H_row *)
Theorem row_height_contains_all_cell_heights :
  forall (spec_h : nat) (cells : list CellBaselineInfo) (c : CellBaselineInfo),
    In c cells ->
    let m := layout_table_row spec_h cells in
    row_block_size m >= cell_content_height c.
Proof.
  intros spec_h cells c HIn m.
  unfold m, layout_table_row, compute_row_height; simpl.
  pose proof (in_max_content_height cells c HIn) as Hmax.
  lia.
Qed.

(** Invariant 3b: Geometric Box Containment for Baseline-Aligned Cells.
    Proves that after shifting a baseline-aligned cell by (max_ascent - ascent(c)),
    its