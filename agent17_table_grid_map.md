### 1. Core Data Structures in Blink Table Cell Mapping

In Chromium’s LayoutNG table engine (`third_party/blink/renderer/core/layout/table/`), table grid formation bridges the DOM/box tree and the 2D layout coordinate space.

#### `NGTableNode` & `NGTableGroupedChildren`
Before grid slot allocation, `NGTableGroupedChildren` normalizes the table's box tree children by partitioning them into structural bands:
*   **Header (`thead`)**: `header` (optional single section, first encountered `LayoutNGTableSection` with `kTableHeaderGroup`).
*   **Bodies (`tbody`)**: `bodies` (`HeapVector<NGBlockNode>`).
*   **Footer (`tfoot`)**: `footer` (optional single section, first encountered `kTableFooterGroup`).
*   **Columns (`col` / `colgroup`)**: `columns` (`HeapVector<NGBlockNode>`).
*   **Captions (`caption`)**: `captions` (`HeapVector<NGBlockNode>`).

Iteration over rows during grid construction walks `header`, then `bodies` in tree order, then `footer`.

#### `NGTableTypes::CellSpan` (Rowspan & Colspan Representation)
Blink bounds cell occupancy along both axes using half-open intervals `[start, end)`:
*   **`wtf_size_t start_row` / `wtf_size_t start_column`**: The 0-based origin coordinates $(r_0, c_0)$ of the cell.
*   **`wtf_size_t colspan`**: Parsed from the `colspan` attribute or defaulted to $1$. Clamped to `[1, kMaxColSpan]` where `kMaxColSpan = 1000` (`html_table_cell_element.h`).
*   **`wtf_size_t rowspan`**: Parsed from the `rowspan` attribute. Clamped to `[0, kMaxRowSpan]` where `kMaxRowSpan = 65534`. A raw `rowspan="0"` (only valid in HTML mode, not quirks mode in certain legacy paths, though HTML5 standardizes it) signals that the cell spans until the end of its enclosing table section (`<thead>`, `<tbody>`, or `<tfoot>`). During section finalization, `rowspan == 0` is resolved to `section_end_row - cell_start_row`.

#### `NGTableGridCell` & Slot Occupancy State
During the layout pass (`NGTableLayoutAlgorithm`), Blink does not materialize a dense $R \times C$ matrix of pointers for the entire table if it can avoid it during column constraint collection; instead, it tracks *active rowspans* and cell inline constraints (`NGTableTypes::CellInlineConstraint` and `CellBlockConstraint`). However, at the structural grid-mapping layer (and in `LayoutTableSection` / accessibility / border-collapse engines), a grid slot is modeled by:
*   **Origin Cell**: The `NGBlockNode` (wrapping `LayoutTableCell`) placed at $(r_0, c_0)$.
*   **Spanned Slots**: Coordinates $(r, c) \in [r_0, r_0 + \text{rowspan}) \times [c_0, c_0 + \text{colspan})$.
*   **Overlap Vector**: Due to HTML §4.9.11 dynamics (detailed in Section 3), a single coordinate $(r, c)$ can be covered by multiple cells if a prior row's cell spans across columns that a subsequent row's cell also spans across.

---

### 2. The Grid Formation Algorithm

The Blink table grid formation algorithm implements HTML Standard §4.9.11 (*"Forming a table"*) and CSS 2.1 §17.5.

```
ALGORITHM: FormTableGrid(GroupedChildren)
CONSTANTS:
  kMaxColSpan = 1000
  kMaxRowSpan = 65534

STATE:
  y_current = 0
  x_width = 0
  y_height = 0
  occupied_slots = Set of (row, col) -> List<CellID>
  cells_GrowingDownward = List of (CellID, start_col, colspan)
```

#### Step-by-Step Execution per Section (`thead`, each `tbody`, `tfoot`):
1.  **Section Initialization**:
    Let $R_{\text{section}}$ be the ordered list of `tr` nodes in the current section. If $R_{\text{section}}$ is empty, advance to the next section.
2.  **Row Iteration**:
    For each `tr` node at global row index $y_{\text{current}}$:
    *   Initialize the column cursor: $x_{\text{current}} \leftarrow 0$.
    *   **Advance Downward-Growing Cells**: For any cell in `cells_GrowingDownward` (originating from `rowspan=0` in earlier rows of the *same* section), mark slots $\{y_{\text{current}}\} \times [c_{\text{start}}, c_{\text{start}} + \text{colspan})$ as occupied in `occupied_slots`.
    *   **Cell Iteration**: For each `td`/`th` child $C_i$ of the current `tr`:
        1.  **Skip Occupied Slots**:
            While $(y_{\text{current}}, x_{\text{current}}) \in \text{occupied\_slots}$:
            $$x_{\text{current}} \leftarrow x_{\text{current}} + 1$$
        2.  **Clamp Spans**:
            $$\text{colspan} \leftarrow \min(\max(\text{raw\_colspan}(C_i), 1), 1000)$$
            $$\text{raw\_rs} \leftarrow \min(\text{raw\_rowspan}(C_i), 65534)$$
            If $\text{raw\_rs} == 0$:
                $\text{grows\_downward} \leftarrow \text{true}$; $\text{rowspan} \leftarrow 1$
            Else:
                $\text{grows\_downward} \leftarrow \text{false}$; $\text{rowspan} \leftarrow \text{raw\_rs}$
        3.  **Update Grid Dimensions**:
            $$x_{\text{width}} \leftarrow \max(x_{\text{width}}, x_{\text{current}} + \text{colspan})$$
            $$y_{\text{height}} \leftarrow \max(y_{\text{height}}, y_{\text{current}} + \text{rowspan})$$
        4.  **Assign Slot Occupancy**:
            Record $C_i$'s origin at $(y_{\text{current}}, x_{\text{current}})$.
            For $r \in [y_{\text{current}}, y_{\text{current}} + \text{rowspan})$ and $c \in [x_{\text{current}}, x_{\text{current}} + \text{colspan})$:
                Add $C_i$ to $\text{occupied\_slots}(r, c)$.
        5.  **Track `rowspan=0`**:
            If $\text{grows\_downward}$ is true, append $(C_i, x_{\text{current}}, \text{colspan})$ to `cells_GrowingDownward`.
        6.  **Advance Cursor**:
            $$x_{\text{current}} \leftarrow x_{\text{current}} + \text{colspan}$$
    *   Increment row index: $y_{\text{current}} \leftarrow y_{\text{current}} + 1$.
3.  **Section Finalization (End of Section Clamping)**:
    *   Clear `cells_GrowingDownward` (their spans terminate at $y_{\text{current}}$).
    *   **Blink vs. HTML Section Rowspan Truncation**: In Blink's `NGTableLayoutAlgorithm`, a cell's `rowspan` cannot cross a section boundary (`thead`, `tbody`, `tfoot`). Any remaining downward span $y_{\text{current}} + \text{rowspan} > y_{\text{section\_end}}$ is clamped so that $r_{\text{end}} = y_{\text{section\_end}}$. Consequently, $y_{\text{height}}$ at the end of a section is strictly equal to $y_{\text{current}}$.

---

### 3. Handling Missing Cells and Overlapping Cells

#### Missing Cells (Implicit Empty Grid Slots)
When a row `tr` finishes processing all its explicit `td`/`th` children and $x_{\text{current}} < x_{\text{width}}$ (or when subsequent rows expand $x_{\text{width}}$ beyond a prior row's final $x_{\text{current}}$), the unassigned coordinates $(r, c) \notin \text{dom}(\text{occupied\_slots})$ are **missing cells** (implicit empty grid slots).
*   **Layout Impact**: They contribute $0\text{px}$ to intrinsic column sizing (`NGTableConstraintSpace`).
*   **Painting & Borders**: Under `border-collapse: separate`, no box is painted (equivalent to `empty-cells: hide` with no border/background). Under `border-collapse: collapse`, the slot participates in border conflict resolution as a cell with `border: none` around its edges, allowing adjacent cells, rows, sections, or table borders to resolve against the empty slot's edges.

#### Overlapping Cells
How can two cells overlap if the cursor skips occupied slots?
Consider a 2-row table:
*   Row 0: Cell $A$ at $(0,0)$ with `colspan=1, rowspan=1`; Cell $B$ at $(0,1)$ with `colspan=1, rowspan=2`.
    Occupied after Row 0: $(0,0) \mapsto [A]$, $(0,1) \mapsto [B]$, $(1,1) \mapsto [B]$.
*   Row 1: Cell $C$ has `colspan=2, rowspan=1`.
    1. Cursor starts at $x_{\text{current}} = 0$.
    2. Is $(1,0)$ occupied? **No**. The `while` loop terminates immediately!
    3. Cell $C$ is placed at origin $(1,0)$ with `colspan=2`.
    4. Cell $C$ claims slots $(1,0)$ and $(1,1)$.
    5. Slot $(1,1)$ is now occupied by **both** $B$ and $C$: $\text{occupied\_slots}(1,1) = [B, C]$.

**Blink Resolution of Overlapping Cells**:
*   **Origin Uniqueness**: Even when cells overlap at $(1,1)$, their origins are $(0,1)$ and $(1,0)$—strictly distinct.
*   **Layout Sizing (`NGTableLayoutAlgorithm`)**: Both cells contribute their inline size constraints to column $1$, and their block size constraints to row $1$.
*   **Fragment Placement & Painting**: Both cells receive layout geometry spanning column $1$ in row $1$; they are painted in DOM tree order (CSS 2.1 Appendix E), causing Cell $C$ to paint over Cell $B$ at slot $(1,1)$.

---

### 4. Mathematical Invariants

Let $R = y_{\text{height}}$ and $C = x_{\text{width}}$ be the final grid dimensions, and let $\mathcal{C}$ be the finite set of placed cells. For each cell $k \in \mathcal{C}$, let its origin be $(r_k, c_k)$ and its clamped spans be $(\Delta r_k, \Delta c_k) \in \mathbb{N}_{\ge 1}^2$, defining its bounding box $B_k = [r_k, r_k + \Delta r_k) \times [c_k, c_k + \Delta c_k)$.

1.  **Coordinate Space Partitioning**:
    Every coordinate $(r, c) \in [0, R) \times [0, C)$ is partitioned into exactly one of three disjoint states:
    $$\mathcal{G} = \mathcal{S}_{\text{empty}} \sqcup \mathcal{S}_{\text{single}} \sqcup \mathcal{S}_{\text{overlap}}$$
    where $\text{Occ}(r,c) = \{ k \in \mathcal{C} \mid (r,c) \in B_k \}$, and:
    *   $\mathcal{S}_{\text{empty}} = \{ (r,c) \mid |\text{Occ}(r,c)| = 0 \}$
    *   $\mathcal{S}_{\text{single}} = \{ (r,c) \mid |\text{Occ}(r,c)| = 1 \}$
    *   $\mathcal{S}_{\text{overlap}} = \{ (r,c) \mid |\text{Occ}(r,c)| \ge 2 \}$
    Furthermore, for all $k \in \mathcal{C}$, $B_k \subseteq [0, R) \times [0, C)$.

2.  **Disjointness of Cell Origins (No Two Origins Overlap)**:
    For any two distinct cells $i, j \in \mathcal{C}$ ($i \neq j$), not only are their origins distinct, but the later cell's origin cannot lie anywhere inside an earlier cell's bounding box:
    $$i <_{\text{DOM}} j \implies (r_j, c_j) \notin B_i$$
    In particular, $(r_i, c_i) \neq (r_j, c_j)$.

3.  **Strict Monotonicity of Slot Progression**:
    *   Across rows: $r_i$ is monotonically non-decreasing with respect to DOM order: $i <_{\text{DOM}} j \implies r_i \le r_j$.
    *   Within the same row ($r_i = r_j$): Since $\Delta c_i \ge 1$ and the cursor only increments during the occupied-slot skip loop, horizontal origins are strictly increasing:
        $$(i <_{\text{DOM}} j \land r_i = r_j) \implies c_i + \Delta c_i \le c_j \implies c_i < c_j$$

4.  **Determinism**:
    The grid formation function is a pure total function from the normalized input tree `TableGroupedChildren` to the final grid state.

---

### 5. Rocq / Coq Formalization (`BlinkTableGridMapSemantics.v`)

The following self-contained Rocq (Coq) development formalizes Blink's clamping rules, grid slot occupancy map, row-by-row and cell-by-cell transition semantics, and proves the core structural invariants: determinism, boundedness of spans, monotonic column cursor progression, and non-overlapping cell origins.

```coq
(** * BlinkTableGridMapSemantics.v
    Formalization of Chromium Blink Table Grid Formation & Cell Slot Occupancy
    per HTML Standard §4.9.11 and CSS 2.1 §17.5. *)

From Coq Require Import Arith PeanoNat Lia Bool List.
Import ListNotations.

(** ** 1. Constants and Clamping Semantics *)

Definition kMaxColSpan : nat := 1000.
Definition kMaxRowSpan : nat := 65534.

Definition clamp_colspan (raw_colspan : nat) : nat :=
  Nat.min (Nat.max raw_colspan 1) kMaxColSpan.

(** In Blink, raw_rowspan = 0 means span until the end of the section.
    Given [remaining_rows_in_section >= 1], we resolve and clamp the span. *)
Definition resolve_and_clamp_rowspan (raw_rowspan remaining_rows_in_section : nat) : nat :=
  let clamped_raw := Nat