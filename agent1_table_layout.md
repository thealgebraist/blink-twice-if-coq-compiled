### 1. Core Data Structures in Blink Table Layout

Blink’s LayoutNG table engine (`third_party/blink/renderer/core/layout/table/`) decouples the DOM tree from the geometric grid. It builds normalized, immutable intermediate structures before running the layout algorithms (`TableLayoutAlgorithm`).

```
+-----------------------------------------------------------------------+
|                         TableGroupedChildren                          |
|  +---------------+  +-------------------------+  +-----------------+  |
|  |    header     |  |         bodies          |  |     footer      |  |
|  | (Opt<Node>)   |  |  (HeapVector<Node>)     |  |  (Opt<Node>)    |  |
|  +---------------+  +-------------------------+  +-----------------+  |
|  +-----------------------------------------------------------------+  |
|  |                   columns (HeapVector<Node>)                    |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
                                   |
                                   v (Slot Placement & Normalization)
+-----------------------------------------------------------------------+
|                    TableGrid / Constraint Space                       |
|                                                                       |
|   Col 0            Col 1            Col 2            Col 3            |
|  +----------------+----------------+----------------+--------------+  |
|  | Cell (0,0)     | Cell (0,1) [colspan=2]          | Cell (0,3)   |  |
|  | [rowspan=2]    +----------------+----------------+--------------+  |
|  |                | Cell (1,1)     | Cell (1,2)     | Cell (1,3)   |  |
|  +----------------+----------------+----------------+--------------+  |
+-----------------------------------------------------------------------+
                                   |
                                   v (Track Sizing & Distribution)
+-----------------------------------------------------------------------+
|                  Vector<TableColumnLocation>                          |
|  [ {offset: d_0, size: w_0}, {offset: d_1, size: w_1}, ... ]          |
+-----------------------------------------------------------------------+
```

#### `TableGroupedChildren`
Constructed during the initial pass over the table's immediate children (`table_layout_utils.cc`). Because HTML permits out-of-order section declarations (e.g., `<tfoot>` before `<tbody>`), `TableGroupedChildren` normalizes the visual and layout order into explicit buckets:
*   `captions`: `HeapVector<BlockNode>` — `display: table-caption` elements.
*   `columns`: `HeapVector<LayoutInputNode>` — `display: table-column` and `display: table-column-group` elements.
*   `header`: `std::optional<BlockNode>` — The first `display: table-header-group` encountered. Subsequent headers are demoted to the `bodies` vector.
*   `bodies`: `HeapVector<BlockNode>` — `display: table-row-group` elements.
*   `footer`: `std::optional<BlockNode>` — The first `display: table-footer-group` encountered. Subsequent footers are demoted to `bodies`.

#### `TableSection`, `TableRow`, `TableCell` (LayoutInputNodes & Constraint Data)
In LayoutNG, `LayoutTableSection`, `LayoutTableRow`, and `LayoutTableCell` are wrapped by `BlockNode` and `TableNode`, while their layout metrics are pre-aggregated into `TableTypes` helper structures (`table_types.h`) to prevent repeated DOM traversals:
*   **`TableCell` (`TableTypes::CellInlineConstraint` & `CellBlockConstraint`)**:
    *   `min_max_sizes`: `{LayoutUnit min_size, LayoutUnit max_size}` representing the cell's min-content and max-content inline contributions.
    *   `css_percentage`: `std::optional<float>` — Resolved percentage inline-size.
    *   `is_constrained`: `bool` — True if the cell has an explicit fixed inline-size (`width != auto`).
    *   `colspan` / `rowspan`: Clamped integer spans (`1 <= colspan <= 1000`, `1 <= rowspan <= 65534`).
    *   `effective_rowspan`: The actual number of rows spanned within the parent section (truncated if `row_index + rowspan > section_row_count`).
    *   `borders`: `BoxStrut` containing the resolved border widths (either separated borders or collapsed border half-widths).
*   **`TableRow` (`TableTypes::Row`)**:
    *   `baseline`: `std::optional<LayoutUnit>` — The shared typographic baseline of all baseline-aligned cells in this row.
    *   `block_size`: `LayoutUnit` — Resolved height of the row.
    *   `start_cell_index`, `cell_count`: Pointers into a flattened cell vector.
    *   `has_rowspan_start`: `bool` — Optimization flag indicating if a multi-row cell originates here.
    *   `is_collapsed`: `bool` — True if `visibility: collapse` is applied.
*   **`TableSection` (`TableTypes::Section`)**:
    *   `start_row_index`, `row_count`: Bounds within the table-wide `Rows` vector.
    *   `percent`: `std::optional<float>` — Explicit percentage block-size if specified on `<tbody>`/`<thead>`/`<tfoot>`.
    *   `is_tbody`: `bool` — Used during block-size distribution (bodies are prioritized over headers/footers for unconstrained block redistribution).

#### `TableColumnLocation`
After column widths are resolved, `ComputeColumnLocations` generates a `Vector<TableColumnLocation>` passed into the `ConstraintSpace` of child sections and rows:
*   `offset`: `LayoutUnit` — The inline-start offset of the column relative to the table's border-box inline-start (incorporates `border-spacing` and inline-start table borders/padding).
*   `size`: `LayoutUnit` — The computed inline-size of the column.
*   `is_collapsed`: `bool` — Set if the `<col>` or `<colgroup>` has `visibility: collapse`. When true, the column's visual geometry is zeroed out (`size = 0`) and adjacent border spacings are collapsed, though its original width may still be used to compute the table's container inline-size per CSS 2.1 §17.5.5.

---

### 2. Fixed vs. Auto Table Layout Algorithms

Blink selects the layout strategy based on the `table-layout` CSS property and the table's inline-size constraint (`table_layout_utils.cc`).

#### A. Fixed Table Layout (`table-layout: fixed`)
If `table-layout: fixed` is specified *and* the table's inline-size is definite (not `auto`), Blink uses a single-pass $O(N_{\text{cols}})$ algorithm defined in `SynchronizeAssignableTableInlineSizeAndColumnsFixed`. If the table's inline-size is `auto`, Blink falls back to the Auto Table Layout algorithm.

1.  **Column Collection (`<col>` pass)**: Iterate over `<col>` elements. Any `<col>` with an explicit fixed `width` or `percentage` sets the initial constraint for that column index $c$.
2.  **First Row Inspection**: Locate the very first row in the visual order (checking `header`, then `bodies[0]`, then `footer`).
    *   For each cell in this row starting at column $c$ with span $S$:
    *   If the cell has an explicit fixed width $W_{\text{cell}}$ or percentage $P_{\text{cell}}$, and the underlying columns $[c, c+S-1]$ do not yet have widths assigned by `<col>`, divide the cell's constraint evenly across all $S$ columns:
        $$\forall i \in [c, c+S-1], \quad W_{\text{col}}[i] = \frac{W_{\text{cell}} - (S - 1) \cdot \text{spacing}_{\text{inline}}}{S}, \quad P_{\text{col}}[i] = \frac{P_{\text{cell}}}{S}$$
    *   *Note*: Cells in rows $> 0$ are completely ignored for inline column sizing. Intrinsic content sizes (`min-content`/`max-content`) of cells in the first row are only measured if the cell has `width: auto`? **No**: in fixed layout, if a cell in row 0 has `width: auto`, its content is *not* measured; the column remains unconstrained (`auto`).
3.  **Distribution of Assignable Table Inline-Size ($W_{\text{avail}}$)**:
    Let $W_{\text{avail}}$ be the table's content-box inline-size minus $(N_{\text{cols}} + 1) \cdot \text{spacing}_{\text{inline}}$.
    *   Fixed columns receive $W[i] = W_{\text{col}}[i]$.
    *   Percentage columns receive $W[i] = \lfloor P_{\text{col}}[i] \cdot W_{\text{avail}} \rfloor$. If the sum of fixed and percentage columns exceeds $W_{\text{avail}}$, percentage columns are clamped/scaled down so the total does not exceed $W_{\text{avail}}$ (or if fixed columns alone exceed $W_{\text{avail}}$, percentage columns resolve to $0$).
    *   Let $W_{\text{rem}} = \max\left(0, W_{\text{avail}} - \sum_{\text{fixed}} W[i] - \sum_{\text{percent}} W[i]\right)$.
    *   **Case 1 (Unconstrained columns exist)**: If the count of `auto` columns $N_{\text{auto}} > 0$, $W_{\text{rem}}$ is distributed equally among them: $W[i] = \frac{W_{\text{rem}}}{N_{\text{auto}}}$.
    *   **Case 2 (All columns constrained, $W_{\text{rem}} > 0$)**: $W_{\text{rem}}$ is distributed proportionally among all non-zero columns (or equally if all fixed widths are $0$).

#### B. Auto Table Layout (`table-layout: auto`)
Defined in CSS 2.1 §17.5.2.2 (non-normative) and standardized in the CSS Tables Module Level 3 draft, Blink implements a multi-pass constraint-aggregation and distribution algorithm (`ComputeColumnConstraints` and `DistributeTableInlineSizeToComputedInlineSizeAuto`).

##### Pass 1: Base Column Constraint Extraction ($\text{colspan} = 1$)
For every column $i \in [0, N_{\text{cols}}-1]$, Blink initializes a `TableTypes::Column` struct:
*   `min_inline_size` ($m_i$), `max_inline_size` ($M_i$), `percent` ($p_i$), `is_constrained` ($c_i$).
*   Constraints from `<col>` elements are applied first.
*   All cells with $\text{colspan} = 1$ in column $i$ are aggregated:
    $$m_i = \max(m_{i,\text{col}}, \max_{\text{cells}} m_{\text{cell}})$$
    $$M_i = \max(M_{i,\text{col}}, \max_{\text{cells}} M_{\text{cell}})$$
    $$p_i = \max(p_{i,\text{col}}, \max_{\text{cells}} p_{\text{cell}})$$
    If a cell has an explicit fixed width $W_{\text{css}}$, then $m_{\text{cell}} = \max(m_{\text{content}}, W_{\text{css}})$ (unless `overflow` is non-visible/clip, where $m_{\text{cell}}$ may be smaller) and $M_{\text{cell}} = \max(m_{\text{cell}}, W_{\text{css}})$, marking $c_i = \text{true}$.
    Finally, enforce invariant $M_i = \max(m_i, M_i)$.

##### Pass 2: Colspan Cell Redistribution ($\text{colspan} > 1$)
Cells with $\text{colspan} > 1$ are sorted and processed to inflate the underlying $[m_i, M_i, p_i]$ values (detailed in Section 3).

##### Pass 3: Table Inline-Size Resolution (GRIDMIN and GRIDMAX)
Let $S_{\text{total}} = (N_{\text{cols}} + 1) \cdot \text{spacing}_{\text{inline}} + \text{borders}_{\text{inline}}$.
*   $\text{GRIDMIN} = \sum_{i=0}^{N-1} m_i + S_{\text{total}}$.
*   $\text{GRIDMAX}$ accounts for percentage columns scaling up the table width, capped at a total percentage sum of $100\%$:
    $$\text{GRIDMAX} = \max\left(\sum_{i} M_i, \max_{i \text{ with } p_i > 0} \left(\frac{M_i}{p_i}\right)\right) + S_{\text{total}}$$
    *(Note: In Blink, when computing intrinsic sizes of the table itself to report to its parent, percentage columns do not reverse-inflate `GRIDMAX`; however, during internal column distribution, percentages resolve against the assignable table width).*

##### Pass 4: Distributing Assignable Width ($W_{\text{avail}}$) to Columns
Blink classifies every column into mutually exclusive priority buckets and interpolates between minimum and maximum bounds based on how $W_{\text{avail}}$ compares to the sum of column widths at each threshold.

Let the thresholds be:
1.  **Zero**: $0$
2.  **Min-Content**: $\sum m_i$
3.  **Percent-Resolved Min**: Each percentage column $i$ desires $w_i = \max(m_i, p_i \cdot W_{\text{avail}})$. (If $\sum p_i > 100\%$, percentages are normalized: $p'_i = \frac{p_i}{\sum p_j}$).
4.  **Max-Content (Constrained Fixed)**: Fixed columns reach their $M_i$.
5.  **Max-Content (All)**: Unconstrained (`auto`) columns reach their $M_i$.

If $W_{\text{avail}} \le \sum m_i$:
Every column receives $W[i] = m_i$ (the table overflows its specified width if $W_{\text{avail}} < \sum m_i$).

If $\sum m_i < W_{\text{avail}} < \sum M'_i$ (where $M'_i$ incorporates resolved percentages):
The excess space $\Delta = W_{\text{avail}} - \sum m_i$ is distributed in strict priority tiers:
1.  First, percentage columns grow from $m_i$ toward $\max(m_i, p_i \cdot W_{\text{avail}})$.
2.  Next, fixed-width constrained columns grow from $m_i$ toward $M_i$.
3.  Next, auto (unconstrained) columns grow from $m_i$ toward $M_i$.
Within any tier that cannot be fully satisfied, the remaining $\Delta$ is distributed proportionally to each column's **growth potential** $g_i = M_i - m_i$:
$$W[i] = m_i + \Delta \cdot \frac{M_i - m_i}{\sum_{j \in \text{tier}} (M_j - m_j)}$$

If $W_{\text{avail}} > \sum M'_i$ (Excess space beyond all max-content sizes):
Let $\Delta_{\text{excess}} = W_{\text{avail}} - \