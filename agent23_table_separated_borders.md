### 1. Core Data Structures in Blink (Separated Borders)

In Chromium Blink’s LayoutNG table architecture (`third_party/blink/renderer/core/layout/table/`), the separated borders model (CSS 2.1 §17.6.1, `border-collapse: separate`) is the default mode. Unlike collapsed borders—which require constructing a global grid of shared edge segments (`TableBorders`)—the separated model delegates border geometry directly to the box model of the table wrapper and individual cells.

*   **`ETableBorderCollapse` & `ComputedStyle`**:
    *   When `style.BorderCollapse() == EBorderCollapse::kSeparate`, `TableBorders::ComputeTableBorders` does not allocate a collapsed edge array. Instead, the `TableBorders` object acts as a pass-through to the table's own `ComputedStyle` border and padding properties.
*   **`border_spacing` (`LogicalSize`)**:
    *   Extracted via `table_node.Style().HorizontalBorderSpacing()` and `VerticalBorderSpacing()` and converted to logical coordinates based on the table’s `WritingMode`:
        $$\text{border\_spacing} = \text{LogicalSize}(\text{inline\_spacing}, \text{block\_spacing})$$
    *   Per CSS 2.1 §17.6.1, negative values are illegal and clamped to $\ge 0$ during style resolution (`LayoutUnit` $\ge 0$).
*   **`TableLayoutAlgorithm` & `TableTypes`**:
    *   `TableTypes::Columns`: Stores column constraints. Spacing is *not* baked into the column structs themselves, but passed alongside them into `SynchronizeAssignableTableInlineSize` and `ComputeColumnLocations`.
    *   `TableColumnLocation`: Represents the resolved inline geometry of a column:
        ```cpp
        struct TableColumnLocation {
          LayoutUnit offset; // Inline offset relative to table border-box
          LayoutUnit size;   // Resolved inline width of the column
          bool is_collapsed; // Visibility: collapse handling
        };
        ```
*   **`TableCellLayoutAlgorithm`**:
    *   Because borders are separated, a cell's border-box is self-contained. Its `BoxStrut` (borders + padding) is computed directly from the cell's own `ComputedStyle` without querying neighboring cells.

---

### 2. Geometry Resolution

Let the table grid consist of $C$ columns ($0 \le c < C$) and $R$ rows ($0 \le r < R$). Let:
*   $B_{\text{inline\_start}}, B_{\text{inline\_end}}, B_{\text{block\_start}}, B_{\text{block\_end}} \ge 0$ be the table’s own borders.
*   $P_{\text{inline\_start}}, P_{\text{inline\_end}}, P_{\text{block\_start}}, P_{\text{block\_end}} \ge 0$ be the table’s own padding.
*   $s_h = \text{inline\_spacing} \ge 0$ and $s_v = \text{block\_spacing} \ge 0$.
*   $w_i \ge 0$ be the resolved width of column $i$, and $h_j \ge 0$ be the resolved height of row $j$.

#### Inline Axis (Columns and Cell X-Coordinates)
The initial inline offset before the first column includes the table's start border, start padding, and one initial horizontal border-spacing:
$$\text{offset}_{\text{init\_inline}} = B_{\text{inline\_start}} + P_{\text{inline\_start}} + s_h$$

For column $c \in [0, C-1]$, the inline offset $\text{cell\_x}(c)$ (represented as `column_locations[c].offset`) is:
$$\text{cell\_x}(c) = B_{\text{inline\_start}} + P_{\text{inline\_start}} + s_h + \sum_{i=0}^{c-1} (w_i + s_h)$$

For a cell at column $c$ with column span $\text{span}_c \ge 1$ (where $c + \text{span}_c \le C$), its total border-box inline size is the sum of the spanned columns plus the internal horizontal spacings between them:
$$\text{cell\_width}(c, \text{span}_c) = \left(\sum_{i=c}^{c + \text{span}_c - 1} w_i\right) + (\text{span}_c - 1) \cdot s_h$$

The total table border-box inline size ($W_{\text{table}}$) for $C > 0$ columns is:
$$W_{\text{table}} = B_{\text{inline\_start}} + P_{\text{inline\_start}} + \left(\sum_{i=0}^{C-1} w_i\right) + (C + 1) \cdot s_h + P_{\text{inline\_end}} + B_{\text{inline\_end}}$$
*(Note: In Blink, if $C = 0$, the spacing term $(C+1)\cdot s_h$ drops to $0$).*

#### Block Axis (Rows and Cell Y-Coordinates)
Table sections (`<thead>`, `<tbody>`, `<tfoot>`) do not have their own borders or padding in CSS 2.1. In Blink, rows are laid out sequentially across sections, separated uniformly by $s_v$. Flattening the rows across all non-empty sections into a global row index $r \in [0, R-1]$:
$$\text{cell\_y}(r) = B_{\text{block\_start}} + P_{\text{block\_start}} + s_v + \sum_{j=0}^{r-1} (h_j + s_v)$$

For a cell at row $r$ with row span $\text{span}_r \ge 1$ ($r + \text{span}_r \le R$), its border-box block size is:
$$\text{cell\_height}(r, \text{span}_r) = \left(\sum_{j=r}^{r + \text{span}_r - 1} h_j\right) + (\text{span}_r - 1) \cdot s_v$$

The total table grid block size ($H_{\text{table}}$, excluding outer table captions) for $R > 0$ rows is:
$$H_{\text{table}} = B_{\text{block\_start}} + P_{\text{block\_start}} + \left(\sum_{j=0}^{R-1} h_j\right) + (R + 1) \cdot s_v + P_{\text{block\_end}} + B_{\text{block\_end}}$$

---

### 3. Border and Background Painting (`TablePainter` & `TableCellPainter`)

In the separated border model, painting follows strict CSS 2.1 §17.5.1 stacking layers and §17.6.1 rules:

1.  **Table Box Painting (`TablePainter::PaintBoxDecorationBackground`)**:
    *   Paints the table's background and the table's outer border around the $W_{\text{table}} \times H_{\text{table}}$ border-box.
    *   **Spacing Transparency**: The regions occupied by `border-spacing` are strictly inside the table's padding-box and outside any cell's border-box. cells and rows cannot paint into the spacing gap; the table's own background shines through the $(C+1)\cdot s_h$ and $(R+1)\cdot s_v$ gaps.
2.  **Section, Column, and Row Backgrounds**:
    *   Even though column groups, columns, row groups, and rows do not have borders in `border-collapse: separate`, their backgrounds are still painted.
    *   However, in Blink’s `TableCellPainter::PaintBackgroundForTablePart`, the background of a row or column is clipped to the **border-box of the individual cells** belonging to that row/column. Row backgrounds *do not* paint across the `border-spacing` gaps between cells (CSS 2.1 §17.5.1).
3.  **Cell Painting (`TableCellPainter`)**:
    *   **`empty-cells` Property**: Before painting a cell's background or borders, Blink checks `style.EmptyCells() == EEmptyCells::kHide`. If true and the cell has no children/content (per CSS 2.1 §17.6.1.1), both the cell's border and its background (as well as the clipped backgrounds of the underlying row/section/column for that cell slot) are completely omitted.
    *   **Independent Box Decoration**: If visible, the cell paints its own background and its 4 borders (`border-top`, `border-right`, `border-bottom`, `border-left`) completely inside its own `[cell_x, cell_x + cell_width] × [cell_y, cell_y + cell_height]` border-box using standard `BoxBackgroundPaintContext` and `BoxBorderPainter`. No edge resolution or half-border miter clipping with adjacent cells occurs.

---

### 4. Mathematical Invariants

1.  **Non-Negativity of Coordinates and Dimensions**:
    $$\forall c, \text{span}_c: \quad \text{cell\_x}(c) \ge 0 \quad \land \quad \text{cell\_width}(c, \text{span}_c) \ge 0$$
2.  **Strict Cell Separation (No Overlap & Exact Gap Conservation)**:
    For any two horizontally adjacent cells where Cell 1 occupies $[c_1, c_1 + \text{span}_{c_1} - 1]$ and Cell 2 begins at $c_2 = c_1 + \text{span}_{c_1}$:
    $$\text{cell\_x}(c_1) + \text{cell\_width}(c_1, \text{span}_{c_1}) + s_h = \text{cell\_x}(c_2)$$
    Since $s_h \ge 0$, the right border-edge of Cell 1 never exceeds the left border-edge of Cell 2:
    $$\text{cell\_x}(c_1) + \text{cell\_width}(c_1, \text{span}_{c_1}) \le \text{cell\_x}(c_2)$$
    If $s_h > 0$, their bounding boxes are strictly disjoint. The identical invariant holds vertically for $s_v$.
3.  **Span Decomposition / Additivity**:
    A cell spanning $\text{span}_c = k_1 + k_2$ columns has the exact same width as two sub-cells of span $k_1$ and $k_2$ plus the intervening $s_h$:
    $$\text{cell\_width}(c, k_1 + k_2) = \text{cell\_width}(c, k_1) + s_h + \text{cell\_width}(c + k_1, k_2)$$
4.  **Total Size Conservation**:
    The right edge of the last column $C-1$ (with $\text{span}_c = 1$) plus the trailing spacing $s_h$, trailing padding, and trailing border equals $W_{\text{table}}$:
    $$\text{cell\_x}(C-1) + \text{cell\_width}(C-1, 1) + s_h + P_{\text{inline\_end}} + B_{\text{inline\_end}} = W_{\text{table}}$$

---

### 5. Rocq / Coq Formalization (`BlinkTableSeparatedBordersSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the data structures, geometry equations, painting visibility rules, and proves the core mathematical invariants using `lia` and list induction.

```coq
(** * BlinkTableSeparatedBordersSemantics.v
    Formalization of Chromium Blink's Separated Table Borders Model
    (CSS 2.1 Section 17.6.1) by Agent 23. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Logical box edges for table borders and padding (in LayoutUnits, modeled as nat). *)
Record BoxStrut : Type := mkBoxStrut {
  inline_start : nat;
  inline_end   : nat;
  block_start  : nat;
  block_end    : nat
}.

(** LogicalSize for border-spacing: inline (horizontal) and block (vertical). *)
Record BorderSpacing : Type := mkBorderSpacing {
  inline_spacing : nat;
  block_spacing  : nat
}.

(** CSS 2.1 17.6.1.1: empty-cells property *)
Inductive EmptyCellsMode : Type :=
  | EmptyCellsShow
  | EmptyCellsHide.

(** Representation of a Table in the Separated Borders model. *)
Record SeparatedTableConfig : Type := mkSeparatedTableConfig {
  table_borders : BoxStrut;
  table_padding : BoxStrut;
  spacing       : BorderSpacing;
  col_widths    : list nat;
  row_heights   : list nat
}.

(** A cell descriptor positioned in the grid with column/row spans. *)
Record TableCell : Type := mkTableCell {
  cell_col      : nat;
  cell_row      : nat;
  col_span      : nat; (* Must be >= 1 *)
  row_span      : nat; (* Must be >= 1 *)
  is_empty      : bool;
  empty_mode    : EmptyCellsMode
}.

(** Bounding box in 2D logical coordinates. *)
Record LogicalRect : Type := mkLogicalRect {
  inline_offset : nat;
  block_offset  : nat;
  inline_size   : nat;
  block_size    : nat
}.

(** ** 2. Helper Functions on Lists (Sums and Slices) *)

Fixpoint sum_list (l : list nat) : nat :=
  match l with
  | [] => 0
  | x :: xs => x + sum_list xs
  end.

Definition slice (l : list nat) (start len : nat) : list nat :=
  firstn len (skipn start l).

Lemma sum_list_app : forall l1 l2,
  sum_list (l1 ++ l2) = sum_list l1 + sum_list l2.
Proof.
  induction l1 as [|x xs IH]; intros l2; simpl; [lia | rewrite IH; lia].
Qed.

Lemma firstn_add : forall (A : Type) (n1 n2 : nat) (l : list A),
  firstn (n1 + n2) l = firstn n1 l ++ firstn n2 (skipn n1 l).
Proof.
  intros A n1; induction n1 as [|n1 IH]; intros n2 l; simpl.
  - reflexivity.
  - destruct l as [|x xs]; simpl; [reflexivity | f_equal; apply IH].
Qed.

Lemma skipn_skipn : forall (A : Type) (n1 n2 : nat) (l : list A),
  skipn n2 (skipn n1 l) = skipn (n1 + n2) l.
Proof.
  intros A n1; induction n1 as [|n1 IH]; intros n2 l; simpl.
  - reflexivity.
  - destruct l as [|x xs