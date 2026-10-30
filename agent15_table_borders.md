### 1. Core Data Structures in Blink LayoutNG

In Chromium’s Blink engine (`third_party/blink/renderer/core/layout/table/`), table border collapsing is orchestrated by `NGTableBorders` (recently refactored to `TableBorders`), which pre-computes a flattened grid of resolved border edges before layout geometry calculation.

#### `TableBorders` (`table_borders.h` / `table_borders.cc`)
Stores the resolved border edges for the entire table grid in two contiguous 1D `WTF::Vector<Edge>` arrays: `horizontal_edges_` and `vertical_edges_`, indexed by grid coordinates $(r, c)$.
* **Grid Dimensions**: If the table has $R$ rows and $C$ columns, `horizontal_edges_` has size $(R + 1) \times C$, and `vertical_edges_` has size $R \times (C + 1)$.
* **Edge Representation**: Each entry in the vector is a compact struct `Edge`:
  ```cpp
  struct Edge {
    const ComputedStyle* style = nullptr;
    EdgeSide edge_side = EdgeSide::kDoNotHaveEdge; // kTop, kRight, kBottom, kLeft, kDoNotHaveEdge
    uint16_t box_order = 0; // Sequence number of the originating DOM box for tie-breaking
  };
  ```
* Rather than duplicating full border values, Blink stores a pointer to the winning `ComputedStyle` and an enum `EdgeSide` indicating which physical side of that style won the conflict.

#### `TableBorderEdge` & `BorderConflictResolution`
During the construction of `TableBorders` (`TableBorders::ComputeTableBorders`), Blink iterates over all table parts in DOM/precedence order:
1. Cells (`LayoutTableCell`)
2. Rows (`LayoutTableRow`)
3. Row Groups (`LayoutTableSection`: `<thead>`, `<tbody>`, `<tfoot>`)
4. Columns (`LayoutTableCol` where `is_column`)
5. Column Groups (`LayoutTableCol` where `is_column_group`)
6. Table (`LayoutTable`)

As each box is visited, its borders are merged into the grid via `MergeRowAxisBorder` and `MergeColumnAxisBorder`. Conflict resolution is implemented in `CompareBorders(const Edge& a, const Edge& b)`:
* Extracts `EBorderStyle` and `LayoutUnit` (width) from `a.style` and `b.style` using `a.edge_side` and `b.edge_side`.
* `box_order` is monotonically incremented for every box visited in the precedence traversal. Since cells are visited before rows, rows before sections, etc., and within each category boxes are visited in visual/DOM order (e.g., left-to-right, top-to-bottom), `box_order` simultaneously encodes **Origin Precedence** and **Positional Tie-Breaking** (top/left wins over bottom/right).

---

### 2. Conflict Resolution Priority Rules (CSS 2.1 §17.6.2.1 vs. Blink)

Given two competing border edges $E_1 = (\text{style}_1, \text{width}_1, \text{origin}_1, \text{pos}_1)$ and $E_2 = (\text{style}_2, \text{width}_2, \text{origin}_2, \text{pos}_2)$, the winning edge is selected via lexicographical comparison:

#### Step 1: Suppress Hidden Borders (`border-style: hidden`)
* **W3C Spec**: If any border has `border-style: hidden`, it unconditionally wins over all other borders. The shared edge is suppressed (drawn as `none` with width `0`).
* **Blink**: `EBorderStyle::kHidden` is checked first. If either edge is `kHidden`, the edge with `kHidden` wins. Its resolved width is forced to `0`.

#### Step 2: Ignore Non-Existent Borders (`border-style: none`)
* **W3C Spec**: If a border has `border-style: none`, it has lowest priority. Only if *all* competing borders are `none` does the edge resolve to `none`.
* **Blink**: If an incoming edge has style `kNone` or width `0` (and is not `kHidden`), it loses to any existing active edge.

#### Step 3: Border Width (`border-width`)
* **W3C Spec**: Narrower borders are discarded in favor of wider ones.
* **Blink**: Compares resolved physical widths (`LayoutUnit`). Note: If `border-style` is `none` or `hidden`, effective width is `0` regardless of the specified `border-width` property. Otherwise, $\text{width}_1 > \text{width}_2 \implies E_1 \text{ wins}$.

#### Step 4: Border Style (`border-style`)
* **W3C Spec & Blink**: If widths are equal, style priority is strictly ordered:
  $$\texttt{double} \succ \texttt{solid} \succ \texttt{dashed} \succ \texttt{dotted} \succ \texttt{ridge} \succ \texttt{outset} \succ \texttt{groove} \succ \texttt{inset}$$
  In Blink (`BorderStylePriority` in `table_borders.cc`), these map to integers $8 \dots 1$.

#### Step 5: Origin Precedence & Positional Tie-Breaking
* **W3C Spec**: If width and style are identical, precedence is:
  $$\texttt{cell} \succ \texttt{row} \succ \texttt{row\_group} \succ \texttt{column} \succ \texttt{column\_group} \succ \texttt{table}$$
  If two elements of the same type conflict, the one further to the left (in `ltr` tables, or right in `rtl`) or further to the top wins.
* **Blink**: Encoded via `box_order`. Because `ComputeTableBorders` visits cells (in row-major order), then rows, then sections, then columns, then column groups, then the table, a strictly smaller `box_order` ($a.\text{box\_order} < b.\text{box\_order}$) guarantees higher precedence.

---

### 3. Border Width Half-Distribution Between Adjacent Cells

In the collapsed border model, borders are centered on the grid lines between cells. To compute layout geometry (`TableBorders::CellBorderWidths` and `ComputeInlineBorderSizes`), the resolved width $W$ of a grid line must be distributed between the two adjacent cells.

Because Blink uses fixed-point subpixel layout (`LayoutUnit`, 1/64th of a pixel) or snapped integer pixels depending on the phase, odd units cannot be split equally without losing 1 quantum of width. Blink enforces conservation of width using an asymmetric split:

1. **Inline-Axis (Vertical Borders: Left vs. Right)**:
   Let $W_{\text{vert}}(r, c)$ be the width of the vertical border at column line $c$.
   * For the cell to the **left** of line $c$ (where line $c$ is its *right* border):
     $$W_{\text{right\_half}} = W_{\text{vert}}(r, c) - \left\lfloor \frac{W_{\text{vert}}(r, c)}{2} \right\rfloor = \left\lceil \frac{W_{\text{vert}}(r, c)}{2} \right\rceil$$
   * For the cell to the **right** of line $c$ (where line $c$ is its *left* border):
     $$W_{\text{left\_half}} = \left\lfloor \frac{W_{\text{vert}}(r, c)}{2} \right\rfloor$$

2. **Block-Axis (Horizontal Borders: Top vs. Bottom)**:
   Let $W_{\text{horiz}}(r, c)$ be the width of the horizontal border at row line $r$.
   * For the cell **above** line $r$ (where line $r$ is its *bottom* border):
     $$W_{\text{bottom\_half}} = W_{\text{horiz}}(r, c) - \left\lfloor \frac{W_{\text{horiz}}(r, c)}{2} \right\rfloor = \left\lceil \frac{W_{\text{horiz}}(r, c)}{2} \right\rceil$$
   * For the cell **below** line $r$ (where line $r$ is its *top* border):
     $$W_{\text{top\_half}} = \left\lfloor \frac{W_{\text{horiz}}(r, c)}{2} \right\rfloor$$

3. **Outer Table Padding / Margin Intrusion**:
   Per CSS 2.1 §17.6.2, only half of the exterior collapsed borders are included in the table's layout width; the other half spills into the margin area. Blink computes the table's intrinsic border box by taking the maximum exterior border along the top, bottom, left, and right perimeter and applying the exact same $\lfloor W/2 \rfloor$ and $\lceil W/2 \rceil$ formula for the inner half.

---

### 4. Mathematical Invariants, Edge Cases, and Implementation Gaps

#### Mathematical Invariants
1. **Strict Weak Ordering of Visual Attributes**: Defining visual comparison $\prec_v$ over $(\text{style}, \text{width})$, $\prec_v$ is a strict weak ordering. When augmented with unique `box_order` IDs, conflict resolution forms a **Strict Total Order**, making the reduction over any sequence of candidate edges associative, commutative, and idempotent (a join-semilattice).
2. **Conservation of Border Width across Boundaries**: For any interior grid segment of resolved width $W \ge 0$, the sum of the border widths allocated to the two adjacent cells is invariant:
   $$\text{LeftCell}_{\text{right\_border}}(W) + \text{RightCell}_{\text{left\_border}}(W) = \left\lceil \frac{W}{2} \right\rceil + \left\lfloor \frac{W}{2} \right\rfloor = W$$
3. **Non-Negativity**: For all resolved edges $E$, $\text{EffectiveWidth}(E) \ge 0$, and both distributed halves are $\ge 0$.

#### Edge Cases & Blink vs. W3C Gaps
1. **RTL Positional Tie-Breaking Gap**:
   * *W3C Spec*: If two cells in the same row share a vertical border with identical width and style, the cell further to the left wins in `ltr` tables, and the cell further to the right wins in `rtl` tables.
   * *Blink Behavior*: Blink converts borders to logical coordinates (`inline-start`, `inline-end`) during `ComputeTableBorders` traversal, which naturally visits inline-start cells before inline-end cells. Thus, Blink correctly respects `direction: rtl` for cell-vs-cell tie-breaking, *except* when physical `left`/`right` styles are mapped back to `EdgeSide` during painting if mixed directionality exists across rows/sections.
2. **Rowspanned / Colspanned Cells (`colspan > 1`, `rowspan > 1`)**:
   * A single cell border can span multiple grid segments, each potentially resolving to a *different* width against adjacent non-spanning cells.
   * *Gap*: While painting draws each grid segment at its individually resolved width, a `LayoutTableCell` must have a single scalar `border_top`, `border_bottom`, `border_left`, and `border_right` for its layout box model. Blink resolves this in `TableBorders::CellBorderWidths` by taking the **maximum** resolved half-width across all spanned segments for that cell side:
     $$\text{CellBorderTop}(r, c, \text{colspan}) = \max_{k=c}^{c+\text{colspan}-1} \left\lfloor \frac{W_{\text{horiz}}(r, k)}{2} \right\rfloor$$
3. **Subpixel vs. Pixel Snapping Discrepancy**:
   * During layout (`TableBorders`), widths are stored as `LayoutUnit` (fixed-point). However, CSS borders are pixel-snapped before layout or during paint (`LayoutUnit(floor(width))`). Because $\lfloor W/2 \rfloor$ in `LayoutUnit` (dividing by 2 in 1/64ths of a pixel) differs from pixel-snapped division when $W$ is an odd number of device pixels, Blink forces border widths in `TableBorders` to be floored to integer CSS pixels early, preventing subpixel drift.

---

### 5. Rocq / Coq Formalization (`BlinkTableBorderCollapseSemantics.v`)

The following standalone, vernacular Coq file formalizes the data structures, priority rules, semilattice conflict resolution, and width distribution invariants, complete with proofs.

```coq
(** * BlinkTableBorderCollapseSemantics.v
    Formalization of Chromium Blink Table Border Collapsing vs W3C CSS 2.1 §17.6.2 *)

From Coq Require Import Arith PeanoNat Lia Bool List Compare_dec.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** CSS 2.1 §17.6.2.1 Border Styles *)
Inductive BorderStyle : Type :=
  | BS_None
  | BS_Inset
  | BS_Groove
  | BS_Outset
  | BS_Ridge
  | BS_Dotted
  | BS_Dashed
  | BS_Solid
  | BS_Double
  | BS_Hidden.

(** CSS 2.1 §17.6.2.1 Element Origin Precedence *)
Inductive BorderOrigin : Type :=
  | BO_Table
  | BO_ColGroup
  | BO_Col
  | BO_RowGroup
  | BO_Row
  | BO_Cell.

(** Representation of a candidate border edge in Blink *)
Record BorderEdge : Type := mkEdge {
  edge_style : BorderStyle;
  edge_raw_width : nat;      (* Width in layout units (non-negative) *)
  edge_origin : BorderOrigin;
  edge_box_order : nat       (* Tie-breaker: smaller means visited earlier (top/left) *)
}.

(** Effective width: 'none' and 'hidden' borders always have 0 effective width *)
Definition effective_width (e : BorderEdge) : nat :=
  match edge_style e with
  | BS_None | BS_Hidden => 0
  | _ => edge_raw_width e
  end.

(** Style priority mapping matching Blink's BorderStylePriority *)
Definition style_priority (s : BorderStyle) : nat :=
  match s with
  | BS_None   => 0
  | BS_Inset  => 1
  | BS_Groove => 2
  | BS_Outset => 3
  | BS_Ridge  => 4
  | BS_Dotted => 5
  | BS_Dashed => 6
  | BS_Solid  => 7
  | BS_Double => 8
  | BS_Hidden => 9 (* Handled specially, highest priority *)
  end.

(** Origin priority mapping: cell > row > row_group > col > col_group > table *)
Definition origin_priority (o : BorderOrigin) : nat :=
  match o with
  | BO_Table    => 0
  | BO_ColGroup => 1
  | BO_Col      => 2
  | BO_RowGroup => 3
  | BO_Row      => 4
  | BO_Cell     => 5
  end.

(** Category rank of an edge for the primary conflict resolution tiers:
    Tier 2: BS_Hidden (wins over all)
