### 1. Core Data Structures in Blink LayoutNG Table Layout

In Chromium’s Blink engine, the LayoutNG table layout phase (`NGTableLayoutAlgorithm`, recently migrated to the unprefixed `TableLayoutAlgorithm` in `third_party/blink/renderer/core/layout/table/`) transforms the layout tree into a normalized $R \times C$ geometric grid before generating immutable physical fragments (`PhysicalBoxFragment`). This satisfies CSS 2.1 §17.5 and CSS Table Module Level 3 §3 (Grid Formation and Geometry).

The core C++ structures that represent this $R \times C$ grid during layout computation are:

*   **`TableGridData` (materialized via `TableTypes::Columns`, `TableTypes::Rows`, and `TableGroupedChildren`):**
    The top-level state held during `TableLayoutAlgorithm::Layout()`. It aggregates the column constraint vector (`TableTypes::Columns`), the resolved column locations (`Vector<TableColumnLocation>`), the global row metrics (`TableTypes::Rows`), and the structural sections (`TableGroupedChildren`).
    ```cpp
    struct TableColumnLocation {
      LayoutUnit offset;
      LayoutUnit size;
      bool is_collapsed;
    };
    ```
*   **`TableRowGroup` (`TableTypes::Section` / `TableChildIterator` over `kTableRowGroup`):**
    Represents `<thead>`, `<tbody>`, and `<tfoot>` layout nodes (`LayoutBlock`). In LayoutNG, row groups do not own an independent column grid; instead, they reference contiguous spans of row indices $[r_{\text{start}}, r_{\text{end}})$ within the parent table's flat `TableTypes::Rows` vector.
*   **`TableRow` (`TableTypes::Row`):**
    Represents a single horizontal grid slot $r \in [0, R)$. It stores the resolved block-size, baseline, and state flags:
    ```cpp
    struct Row {
      LayoutUnit block_size;
      LayoutUnit baseline;
      wtf_size_t start_cell_index;
      wtf_size_t cell_count;
      bool is_collapsed;
      bool has_rowspan_start;
    };
    ```
*   **`TableCell` (`TableTypes::CellBlockConstraint` & `NGTableFragmentData::ColspannedCell`):**
    Represents a grid cell anchored at a primary slot $(r, c)$ with spans $(\Delta r, \Delta c) \ge (1, 1)$. During fragment generation (`TableSectionLayoutAlgorithm` and `TableRowLayoutAlgorithm`), cells are bound to their grid slots via `start_column`, `start_row`, `colspan`, and `rowspan`.

---

### 2. Grid Coordinate Mapping

Let a table have $R$ rows and $C$ columns. In Blink's writing-mode-abstracted logical coordinate space (`LogicalOffset(inline_offset, block_offset)` and `LogicalSize(inline_size, block_size)`):

1.  **Column Positions ($\vec{X}$):**
    `TableLayoutAlgorithm::ComputeLocationsFromColumns` computes a vector of `TableColumnLocation` of length $C$. Given initial border-padding inline-start $x_{\text{init}}$ and inline border-spacing $s_x$:
    $$x_0 = x_{\text{init}} + s_x$$
    $$x_c = x_{c-1} + w_{c-1} + s_x \quad \text{for } 0 < c < C$$
    where $w_c \ge 0$ is the resolved inline-size (`TableColumnLocation::size`) of column $c$ (if column $c$ is collapsed, $w_c = 0$ and its spacing contribution is suppressed).

2.  **Row Offsets ($\vec{Y}$):**
    During section and row layout, block offsets are accumulated across sections and rows. Given initial border-padding block-start $y_{\text{init}}$ and block border-spacing $s_y$:
    $$y_0 = y_{\text{init}} + s_y$$
    $$y_r = y_{r-1} + h_{r-1} + s_y \quad \text{for } 0 < r < R$$
    where $h_r \ge 0$ is the resolved block-size (`TableTypes::Row::block_size`) of row $r$.

3.  **Cell Geometry Mapping:**
    For a `TableCell` originating at grid slot $(r, c)$ with column span $\Delta c \ge 1$ and row span $\Delta r \ge 1$ (clamped per CSS Table 3 §3.5 such that $c + \Delta c \le C$ and $r + \Delta r \le R$):
    *   **Inline Offset:** $\text{InlineOffset}(r, c) = x_c$
    *   **Block Offset:** $\text{BlockOffset}(r, c) = y_r$ (relative to the table grid; relative to the parent `TableRow` fragment, the local block offset is $0$).
    *   **Inline Size:**
        $$\text{InlineSize}(c, \Delta c) = \left( x_{c + \Delta c - 1} + w_{c + \Delta c - 1} \right) - x_c$$
    *   **Block Size:**
        $$\text{BlockSize}(r, \Delta r) = \left( y_{r + \Delta r - 1} + h_{r + \Delta r - 1} \right) - y_r$$

---

### 3. Formal Invariants

To guarantee absence of out-of-bounds memory access in Blink's `WTF::Vector` buffer indexing and to satisfy CSS 2.1 §17.5 box model geometry, the dynamic grid must preserve three core invariants:

1.  **Index Bounds Validity:**
    For every placed cell $k$ with anchor $(r_k, c_k)$ and clamped spans $(\Delta r_k, \Delta c_k)$:
    $$0 \le r_k < R \quad \land \quad 0 \le c_k < C$$
    $$1 \le \Delta r_k \le R - r_k \quad \land \quad 1 \le \Delta c_k \le C - c_k$$

2.  **Row Offset Monotonicity:**
    Because CSS table row heights $h_r$ and border spacings $s_y$ are non-negative (`LayoutUnit >= 0` enforced via `.ClampNegativeToZero()`), the sequence of row block-offsets is monotonically non-decreasing:
    $$\forall r_1, r_2 \in [0, R), \quad r_1 \le r_2 \implies y_{r_1} \le y_{r_2}$$
    Furthermore, for any cell spanning $\Delta r \ge 1$ rows, its computed block-size is non-negative: $\text{BlockSize}(r, \Delta r) \ge h_r \ge 0$.

3.  **Column Coordinate Preservation:**
    Because column widths $w_c \ge 0$ and inline spacings $s_x \ge 0$ are invariant across all rows $r \in [0, R)$, column offsets are strictly preserved across rows and monotonically non-decreasing across column indices:
    $$\forall c_1, c_2 \in [0, C), \quad c_1 \le c_2 \implies x_{c_1} \le x_{c_2}$$
    $$\forall r_1, r_2 \in [0, R), \forall c \in [0, C), \quad \text{InlineOffset}(r_1, c) = \text{InlineOffset}(r_2, c) = x_c$$

---

### 4. Concrete Rocq / Coq Formalization (`BlinkTableDynamicGridSemantics.v`)

The following self-contained Rocq/Coq script models the Blink LayoutNG table grid data structures, coordinate evaluation functions, and proves the three core invariants.

```coq
(** * BlinkTableDynamicGridSemantics.v
    Formalization of Chromium Blink LayoutNG Table Grid Geometry
    against CSS 2.1 Section 17.5 and CSS Table Module Level 3 Section 3. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Core Data Structures *)

(** A column metric represents the resolved inline-size of a column. *)
Record TableColumnMetric := mkColMetric {
  col_inline_size : nat;
  col_is_collapsed : bool
}.

(** A computed column location (Blink's [TableColumnLocation]). *)
Record TableColumnLocation := mkColLoc {
  col_offset : nat;
  col_size   : nat
}.

(** A row metric (Blink's [TableTypes::Row]). *)
Record TableRow := mkRow {
  row_block_size   : nat;
  row_baseline     : nat;
  row_is_collapsed : bool
}.

(** A row group / section (Blink's [TableTypes::Section]) referencing a
    contiguous range of rows [section_start_row, section_start_row + section_row_count). *)
Record TableRowGroup := mkRowGroup {
  section_start_row : nat;
  section_row_count : nat
}.

(** A grid cell positioned in the table (Blink's [TableCell] / [CellBlockConstraint]). *)
Record TableCell := mkCell {
  cell_row     : nat;
  cell_col     : nat;
  cell_rowspan : nat;
  cell_colspan : nat
}.

(** Computed logical geometry of a placed fragment in the table grid. *)
Record LogicalRect := mkRect {
  rect_inline_offset : nat;
  rect_block_offset  : nat;
  rect_inline_size   : nat;
  rect_block_size    : nat
}.

(** Top-level TableGridData structure for an R x C grid. *)
Record TableGridData := mkGridData {
  grid_columns        : list TableColumnMetric;
  grid_rows           : list TableRow;
  grid_row_groups     : list TableRowGroup;
  grid_cells          : list TableCell;
  grid_inline_spacing : nat;
  grid_block_spacing  : nat;
  grid_inline_start   : nat;
  grid_block_start    : nat
}.

(** Dimension accessors. *)
Definition num_cols (g : TableGridData) : nat := length (grid_columns g).
Definition num_rows (g : TableGridData) : nat := length (grid_rows g).

(** ** 2. Coordinate Mapping Semantics *)

(** Computes cumulative offsets from a list of sizes, initial offset [cur], and spacing [sp]. *)
Fixpoint compute_locations (sizes : list nat) (cur sp : nat) : list (nat * nat) :=
  match sizes with
  | [] => []
  | sz :: rest => (cur, sz) :: compute_locations rest (cur + sz + sp) sp
  end.

Definition column_sizes (g : TableGridData) : list nat :=
  map (fun c => if col_is_collapsed c then 0 else col_inline_size c) (grid_columns g).

Definition row_sizes (g : TableGridData) : list nat :=
  map (fun r => if row_is_collapsed r then 0 else row_block_size r) (grid_rows g).

(** Resolved column locations [(offset, size)] for all c in [0, C). *)
Definition resolved_columns (g : TableGridData) : list (nat * nat) :=
  compute_locations (column_sizes g)
                    (grid_inline_start g + grid_inline_spacing g)
                    (grid_inline_spacing g).

(** Resolved row locations [(offset, size)] for all r in [0, R). *)
Definition resolved_rows (g : TableGridData) : list (nat * nat) :=
  compute_locations (row_sizes g)
                    (grid_block_start g + grid_block_spacing g)
                    (grid_block_spacing g).

(** Accessors for the r-th row offset/size and c-th column offset/size. *)
Definition get_col_loc (g : TableGridData) (c : nat) : nat * nat :=
  nth c (resolved_columns g) (0, 0).

Definition get_row_loc (g : TableGridData) (r : nat) : nat * nat :=
  nth r (resolved_rows g) (0, 0).

Definition col_offset_at (g : TableGridData) (c : nat) : nat :=
  fst (get_col_loc g c).

Definition col_size_at (g : TableGridData) (c : nat) : nat :=
  snd (get_col_loc g c).

Definition row_offset_at (g : TableGridData) (r : nat) : nat :=
  fst (get_row_loc g r).

Definition row_size_at (g : TableGridData) (r : nat) : nat :=
  snd (get_row_loc g r).

(** Computes the LogicalRect of a TableCell in GridData [g]. *)
Definition compute_cell_rect (g : TableGridData) (cell : TableCell) : LogicalRect :=
  let r := cell_row cell in
  let c := cell_col cell in
  let end_r := r + cell_rowspan cell - 1 in
  let end_c := c + cell_colspan cell - 1 in
  let x_start := col_offset_at g c in
  let y_start := row_offset_at g r in
  let x_end   := col_offset_at g end_c + col_size_at g end_c in
  let y_end   := row_offset_at g end_r + row_size_at g end_r in
  mkRect x_start y_start (x_end - x_start) (y_end - y_start).

(** ** 3. Validity Predicates & Invariants *)

(** A cell has valid bounds within an R x C grid (CSS Table 3 Section 3.5). *)
Definition valid_cell_bounds (R C : nat) (cell : TableCell) : Prop :=
  cell_row cell < R /\
  cell_col cell < C /\
  1 <= cell_rowspan cell /\
  cell_row cell + cell_rowspan cell <= R /\
  1 <= cell_colspan cell /\
  cell_col cell + cell_colspan cell <= C.

(** A row group is well-formed within R rows. *)
Definition valid_row_group (R : nat) (rg : TableRowGroup) : Prop :=
  section_start_row rg + section_row_count rg <= R.

(** Well-formedness of the entire TableGridData state. *)
Definition wf_grid (g : TableGridData) : Prop :=
  let R := num_rows g in
  let C := num_cols g in
  (forall cell, In cell (grid_cells g) -> valid_cell_bounds R C cell) /\
  (forall rg, In rg (grid_row_groups g) -> valid_row_group R rg).

(** ** 4. Lem