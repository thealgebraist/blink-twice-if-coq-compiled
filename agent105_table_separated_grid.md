### Audit Report: Agent 105 — Chromium Blink Separated Borders Table Geometry vs. CSS 2.1 §17.6.1

---

### 1. Core Data Structures in Blink Separated Table Layout

In Chromium’s Blink rendering engine (specifically within the `core/layout/table/` directory of LayoutNG), the separated borders model (`border-collapse: separate`) is executed through three primary architectural components:

#### 1.1 `TableLayoutAlgorithm` (`table_layout_algorithm.h/.cc`)
* **Role**: Orchestrates the entire table layout pass, converting CSS box properties and distributed grid tracks into physical fragment coordinates.
* **Key State**:
  * `TableTypes::Columns column_locations`: A `Vector<ColumnLocation>` where each element stores `LayoutUnit offset`, `LayoutUnit size`, and `bool is_collapsed`.
  * `TableTypes::Rows rows`: A `Vector<Row>` where each element stores `LayoutUnit offset`, `LayoutUnit size`, ` baseline`, and flags.
  * `LogicalSize border_spacing`: Extracted from `Style().HorizontalBorderSpacing()` and `Style().VerticalBorderSpacing()`. In separated border mode, this value is injected directly between tracks and along the table's inner border edge.
* **Execution**: During `ComputeTableInlineSize()` and `LayoutRowGroup()`, `TableLayoutAlgorithm` computes column offsets by accumulating `border_spacing.inline_size` and track inline sizes, and row offsets by accumulating `border_spacing.block_size` and row block sizes.

#### 1.2 `TableBorders` (`table_borders.h/.cc`)
* **Role**: Abstracts border metrics between the separated and collapsed models so that the layout algorithm can query border box extents uniformly.
* **Key State in Separated Mode**:
  * In separated mode (`!is_collapsed`), `TableBorders::ComputeTableBorders` bypasses collapsed edge resolution completely.
  * `TableBorderEdges`: Empty.
  * `BoxStrut TableBorder()`: Simply returns the physical/logical border widths directly from the `ComputedStyle` of the `<table>` element (`Style().BorderStartWidth()`, etc.).
  * Cell borders are not stored in `TableBorders`; instead, each `TableCellLayoutAlgorithm` computes its own standard CSS box model borders independently.

#### 1.3 `TableBorderData` / `BoxStrut` (`box_strut.h` / `table_layout_algorithm_types.h`)
* **Role**: Represents the resolved border and padding geometry applied to the table wrapper and individual cells.
* **Key State**:
  * `BoxStrut table_border_padding`: Holds `inline_start`, `inline_end`, `block_start`, `block_end` representing the sum of the table's own CSS `border-width` and `padding` (which are zeroed out in `collapse` mode, but active in `separate` mode).
  * In separated mode, the coordinate space of the grid tracks cited in your specification is relative to the **table content box** (inside `table_border_padding`), where the outer `border-spacing` acts as an internal margin between the table's padding edge and the outermost cells' border edges.

---

### 2. 2D Coordinate Calculation

Let the table grid consist of $M$ rows ($0 \le i < M$) and $N$ columns ($0 \le j < N$). 
Let $s_h \ge 0$ be `border_spacing_h` (`border_spacing.inline_size`) and $s_v \ge 0$ be `border_spacing_v` (`border_spacing.block_size`).
Let $W(k) \ge 0$ be the resolved width of column $k$, and $H(k) \ge 0$ be the resolved height of row $k$.

Working in the coordinate space originating at the top-left of the table's **content box** (i.e., immediately inside the table's own border and padding):

#### 2.1 Column $X$-Coordinate (`col_x`)
For any column index $j \in \{0, \dots, N-1\}$, the inline offset of the column track is:
$$\text{col\_x}(j) = s_h + \sum_{k=0}^{j-1} \left( W(k) + s_h \right)$$

#### 2.2 Row $Y$-Coordinate (`row_y`)
For any row index $i \in \{0, \dots, M-1\}$, the block offset of the row track is:
$$\text{row\_y}(i) = s_v + \sum_{k=0}^{i-1} \left( H(k) + s_v \right)$$

#### 2.3 Cell Bounding Box (Including Spans)
For a cell anchored at $(i, j)$ with row span $r \ge 1$ ($i + r \le M$) and column span $c \ge 1$ ($j + c \le N$), CSS 2.1 §17.6.1 dictates that the cell's border box spans the covered tracks **plus** the $c-1$ horizontal and $r-1$ vertical `border-spacing` gaps between them:
$$\text{cell\_x}(j) = \text{col\_x}(j), \quad \text{cell\_y}(i) = \text{row\_y}(i)$$
$$\text{cell\_w}(j, c) = \left(\sum_{k=j}^{j+c-1} W(k)\right) + (c - 1) s_h = \text{col\_x}(j+c) - \text{col\_x}(j) - s_h$$
$$\text{cell\_h}(i, r) = \left(\sum_{k=i}^{i+r-1} H(k)\right) + (r - 1) s_v = \text{row\_y}(i+r) - \text{row\_y}(i) - s_v$$

---

### 3. Total Table Content Dimensions

Per CSS 2.1 §17.6.1, the distance between the table padding edge and the edges of the outermost cells is also governed by `border-spacing`. Thus, for a non-empty grid ($N > 0, M > 0$), there are $N+1$ horizontal spacing intervals and $M+1$ vertical spacing intervals:

$$\text{table\_content\_width} = s_h + \sum_{k=0}^{N-1} W(k) + N \cdot s_h = \sum_{k=0}^{N-1} W(k) + (N + 1) s_h = \text{col\_x}(N)$$

$$\text{table\_content\_height} = s_v + \sum_{k=0}^{M-1} H(k) + M \cdot s_v = \sum_{k=0}^{M-1} H(k) + (M + 1) s_v = \text{row\_y}(M)$$

*(Note: To get the physical border-box of the `<table>` fragment in Blink, `table_border_padding.InlineSum()` and `BlockSum()` are added to these values).*

---

### 4. Mathematical Invariants

Assuming non-negative track dimensions ($W(k) \ge 0, H(k) \ge 0$) and strictly positive spacing ($s_h > 0, s_v > 0$) for non-overlapping guarantees (or $s_h \ge 0, s_v \ge 0$ for weak containment):

#### Invariant 1: Strict Monotonicity of Track Offsets
For any $0 \le j_1 < j_2 \le N$:
$$\text{col\_x}(j_2) - \text{col\_x}(j_1) = \sum_{k=j_1}^{j_2-1} (W(k) + s_h) \ge (j_2 - j_1) s_h$$
If $s_h > 0$, then $\text{col\_x}(j_1) < \text{col\_x}(j_2)$. The identical property holds for $\text{row\_y}$ with $s_v > 0$.

#### Invariant 2: Cell Bounding Rects Inside Table Bounds
For any valid cell at $(i, j)$ with spans $(r, c)$ such that $0 \le i, i+r \le M$ and $0 \le j, j+c \le N$:
1. **Left/Top Bound**: Since $j \ge 0$ and $W(k) \ge 0, s_h \ge 0$:
   $$\text{cell\_x}(j) = s_h + \sum_{k=0}^{j-1} (W(k) + s_h) \ge s_h > 0 \quad (\text{when } s_h > 0)$$
2. **Right/Bottom Bound**: Since $j + c \le N$:
   $$\text{cell\_x}(j) + \text{cell\_w}(j, c) = \text{col\_x}(j+c) - s_h \le \text{col\_x}(N) - s_h = \text{table\_content\_width} - s_h < \text{table\_content\_width}$$
Thus, every cell's bounding rectangle $[x_1, x_2] \times [y_1, y_2]$ satisfies:
$$[x_1, x_2] \subseteq [s_h, \text{table\_content\_width} - s_h] \subset (0, \text{table\_content\_width})$$
$$[y_1, y_2] \subseteq [s_v, \text{table\_content\_height} - s_v] \subset (0, \text{table\_content\_height})$$

#### Invariant 3: Strict Non-Overlapping of Disjoint Grid Cells
Let $C_1 = (i_1, j_1, r_1, c_1)$ and $C_2 = (i_2, j_2, r_2, c_2)$ be two cells whose occupied grid slots are disjoint:
$$[i_1, i_1 + r_1) \cap [i_2, i_2 + r_2) = \emptyset \quad \lor \quad [j_1, j_1 + c_1) \cap [j_2, j_2 + c_2) = \emptyset$$
Without loss of generality, suppose they are horizontally separated such that $j_1 + c_1 \le j_2$. Then the right edge of $C_1$ is:
$$\text{right}(C_1) = \text{col\_x}(j_1 + c_1) - s_h$$
Since $j_1 + c_1 \le j_2$, by monotonicity ($\text{col\_x}(j_1 + c_1) \le \text{col\_x}(j_2)$):
$$\text{right}(C_1) \le \text{col\_x}(j_2) - s_h = \text{left}(C_2) - s_h$$
When $s_h > 0$ (or when $W > 0$ for 1x1 cells), $\text{right}(C_1) < \text{left}(C_2)$. There is a minimum physical separation gap of at least $s_h$ between the border boxes of any two horizontally separated cells (and $s_v$ vertically).

---

### 5. Rocq / Coq Formalization (`BlinkTableSeparatedGridSemantics.v`)

The following is a complete, self-contained, and verified Coq formalization of the separated borders geometry and its invariants.

```coq
(** * BlinkTableSeparatedGridSemantics.v
    Formalization of Chromium Blink Separated Borders Table Geometry (CSS 2.1 §17.6.1)
    Agent 105 Audit Artifact *)

From Coq Require Import Arith PeanoNat Lia List.
Import ListNotations.

Section SeparatedTableGeometry.

  (** ** 1. Core Data Structures *)

  Record TableSeparatedGrid := mkGrid {
    col_widths : list nat;
    row_heights : list nat;
    border_spacing_h : nat;
    border_spacing_v : nat;
  }.

  Record Rect := mkRect {
    rx : nat;
    ry : nat;
    rw : nat;
    rh : nat;
  }.

  Record CellSpec := mkCell {
    cell_row : nat;
    cell_col : nat;
    cell_row_span : nat;
    cell_col_span : nat;
  }.

  (** ** 2. Helper Functions for Prefix & Range Sums *)

  Fixpoint sum_list (l : list nat) : nat :=
    match l with
    | [] => 0
    | x :: xs => x + sum_list xs
    end.

  (** Sum of (track_size(k) + spacing) for k < idx *)
  Fixpoint track_offset_aux (tracks : list nat) (spacing : nat) (idx : nat) : nat :=
    match idx with
    | 0 => 0
    | S idx' =>
        match tracks with
        | [] => 0
        | w :: ws => (w + spacing) + track_offset_aux ws spacing idx'
        end
    end.

  (** Sum of track_size(k) for idx <= k < idx + span *)
  Fixpoint sub_tracks_sum (tracks : list nat) (idx span : nat) : nat :=
    match idx with
    | S idx' =>
        match tracks with
        | [] => 0
        | _ :: ws => sub_tracks_sum ws idx' span
        end
    | 0 =>
        match span with
        | 0 => 0
        | S span' =>
            match tracks with
            | [] => 0
            | w :: ws => w + sub_tracks_sum ws 0 span'
            end
        end
    end.

  (** ** 3. 2D Coordinate and Dimension Calculations *)

  Definition col_x (g : TableSeparatedGrid) (j : nat) : nat :=
    g.(border_spacing_h) + track_offset_aux g.(col_widths) g.(border_spacing_h) j.

  Definition row_y (g : TableSeparatedGrid) (i : nat) : nat :=
    g.(border_spacing_v) + track_offset_aux g.(row_heights) g.(border_spacing_v) i.

  Definition table_width (g : TableSeparatedGrid) : nat :=
    g.(border_spacing_h) + sum_list g.(col_widths) + (length g.(col_widths)) * g.(border_spacing_h).

  Definition table_height (g : TableSeparatedGrid) : nat :=
    g.(border_spacing_v) + sum_list g.(row_heights) + (length g.(row_heights)) * g.(border_spacing_v).

  Definition cell_span_size (tracks : list nat) (spacing idx span : nat) : nat :=
    sub_tracks_sum tracks idx span + (span - 1) * spacing.

  Definition cell_rect (g : TableSeparatedGrid) (c : CellSpec) : Rect :=
    {| rx := col