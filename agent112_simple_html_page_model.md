### 1. End-to-End Operational Pipeline

The complete layout engine executes as a deterministic, purely functional five-stage pipeline transforming a raw HTML Document AST and CSS ruleset into an immutable tree of positioned `PhysicalFragment` geometry.

```
[HTML AST + CSS Rules] 
   │
   ▼ (Stage 1: cascade_dom)
[StyledNode Tree] 
   │
   ▼ (Stage 2: build_layout_tree)
[LayoutBox Tree] 
   │
   ▼ (Stage 3: compute_intrinsic_sizes)
[Sized LayoutBox Tree] 
   │
   ▼ (Stage 4: layout_block_level / layout_table)
[PhysicalFragment Tree]
```

#### Stage 1: Style Resolution (`cascade_dom : DOMNode -> list CSSRule -> StyledNode`)
*   **Input**: A recursive `DOMNode` tree (`Element tag children` or `Text str`) and a flat list of user-agent and author `CSSRule` records.
*   **Operation**: Matches node tags against rule selectors. Combines default User-Agent styles (e.g., `<h1>` gets `display: block; margin-top: 20px; margin-bottom: 20px; height: 32px`, `<table>` gets `display: table`) with matched rules. Computes cascade priority (last-rule-wins for identical specificity) and propagates inherited properties (`font-size`, `line-height`) down to text nodes.
*   **Output**: A `StyledNode` tree where every node is paired with a resolved `ComputedStyle` record.

#### Stage 2: Layout Box Generation (`build_layout_tree : StyledNode -> option LayoutBox`)
*   **Input**: `StyledNode` tree.
*   **Operation**: Filters out nodes with `display: none`. Maps remaining nodes to their structural formatting contexts:
    *   `DisplayBlock` $\rightarrow$ `BlockBox style children`
    *   `DisplayTable` $\rightarrow$ `TableBox style rows`
    *   `DisplayTableRow` $\rightarrow$ `TableRowBox style cells`
    *   `DisplayTableCell` $\rightarrow$ `TableCellBox style content_width content_height`
*   **Canonicalization**: Enforces structural invariants. Any stray text or inline box inside a block container is wrapped in an anonymous block or inline formatting context; table cells measure their raw text children to establish intrinsic content dimensions.

#### Stage 3: Intrinsic Sizing (`compute_column_widths : list TableRowBox -> list nat`)
*   **Input**: The rows of a `TableBox`.
*   **Operation**: Bottom-up pass over the table grid. For each column index $j$, computes the maximum `min-content` / `max-content` width across all cells in column $j$:
    $$W_{\text{col}}[j] = \max_{i} \left( \text{padding\_left}_{i,j} + \text{content\_width}_{i,j} + \text{padding\_right}_{i,j} \right)$$
*   **Output**: A vector of resolved column widths $\vec{W}_{\text{col}}$ and resolved row heights $\vec{H}_{\text{row}}$.

#### Stage 4: Block & Table Layout (`layout_page : LayoutBox -> nat -> PhysicalFragment`)
*   **Input**: Root `LayoutBox` and viewport width $W_{\text{vp}}$.
*   **Block Formatting Context (BFC) State**: Tracks `(current_y : nat, prev_margin_bottom : nat, is_first_child : bool)`.
*   **Margin Collapsing**: When placing a consecutive block child (like `<h1>`, `<h2>`, or `<table>`), the vertical gap between the previous box's bottom border edge and the current box's top border edge is resolved via:
    $$\Delta Y = \begin{cases} \text{margin\_top}_{\text{curr}} & \text{if } \text{is\_first\_child} \\ \max(\text{prev\_margin\_bottom}, \text{margin\_top}_{\text{curr}}) & \text{otherwise} \end{cases}$$
    $$\text{box\_y} = \text{current\_y} + \Delta Y$$
    The state updates for the next sibling to:
    $$\text{current\_y}' = \text{box\_y} + \text{border\_box\_height}_{\text{curr}}, \quad \text{prev\_margin\_bottom}' = \text{margin\_bottom}_{\text{curr}}$$
*   **Table Formatting Context (TFC)**: Invoked when the BFC encounters a `TableBox`.
    *   Iterates through `rows` accumulating $y_{\text{row}}$ offsets starting at $0$ (relative to the table's top-left corner) or directly in page-space starting at $\text{table\_y}$.
    *   For each row $i$, iterates through `cells` accumulating $x_{\text{cell}}$ offsets:
        $$x_{\text{cell}}[i, j] = \sum_{k=0}^{j-1} W_{\text{col}}[k], \quad y_{\text{cell}}[i, j] = \sum_{m=0}^{i-1} H_{\text{row}}[m]$$
*   **Output**: An immutable `PhysicalFragment` tree containing absolute `(x, y, width, height)` bounding boxes for the page, blocks, table, rows, and cells.

---

### 2. Concrete Evaluation Example

#### Source HTML & Implicit UA Stylesheet
```html
<body>
  <h1>Header</h1>
  <h2>Subheader</h2>
  <table>
    <tr><th>H1</th><th>H2</th></tr>
    <tr><td>D1</td><td>D2</td></tr>
  </table>
</body>
```

*   **Viewport Width ($W_{\text{vp}}$)**: `800px`
*   **Character Metrics**: Monospace `10px` width per character, `20px` base line-height.
*   **User-Agent Styles**:
    *   `body`: `display: block; margin: 0px; padding: 0px;`
    *   `h1`: `display: block; height: 32px; margin-top: 20px; margin-bottom: 20px; padding: 0px;`
    *   `h2`: `display: block; height: 24px; margin-top: 15px; margin-bottom: 15px; padding: 0px;`
    *   `table`: `display: table; margin-top: 10px; margin-bottom: 10px; padding: 0px;`
    *   `tr`: `display: table-row;`
    *   `th`: `display: table-cell; padding: 4px; height: 20px;` (Content: `"H1"` = 20px, `"H2"` = 20px)
    *   `td`: `display: table-cell; padding: 4px; height: 20px;` (Content: `"D1"` = 20px, `"D2"` = 20px)

#### Step-by-Step Layout Trace

1.  **Root `<body>` Initialization**:
    *   Starts BFC at `current_y = 0`, `prev_margin_bottom = 0`, `is_first = true`.
2.  **Child 1 (`<h1>Header</h1>`)**:
    *   `is_first = true` $\implies y_{h1} = 0 + \text{margin\_top}_{h1} = 20$.
    *   Width = $W_{\text{vp}} = 800$. Height = $32$.
    *   **Fragment**: `Rect(x: 0, y: 20, w: 800, h: 32)`.
    *   State Update: `current_y = 20 + 32 = 52`, `prev_margin_bottom = 20`, `is_first = false`.
3.  **Child 2 (`<h2>Subheader</h2>`)**:
    *   Margin Collapse: $\Delta Y = \max(\text{prev\_mb}, \text{margin\_top}_{h2}) = \max(20, 15) = 20$.
    *   $y_{h2} = \text{current\_y} + \Delta Y = 52 + 20 = 72$.
    *   Width = $800$. Height = $24$.
    *   **Fragment**: `Rect(x: 0, y: 72, w: 800, h: 24)`.
    *   State Update: `current_y = 72 + 24 = 96`, `prev_margin_bottom = 15`.
4.  **Child 3 (`<table>`)**:
    *   **Intrinsic Sizing**:
        *   Each cell (`H1`, `H2`, `D1`, `D2`) has content width $20\text{px}$ and horizontal padding $4\text{px} + 4\text{px} = 8\text{px}$, yielding border-box width $28\text{px}$.
        *   Each cell has content height $20\text{px}$ and vertical padding $4\text{px} + 4\text{px} = 8\text{px}$, yielding border-box height $28\text{px}$.
        *   Column widths: $W_{\text{col}}[0] = \max(28, 28) = 28$, $W_{\text{col}}[1] = \max(28, 28) = 28$. Total Table Width = $28 + 28 = 56$.
        *   Row heights: $H_{\text{row}}[0] = 28$, $H_{\text{row}}[1] = 28$. Total Table Height = $28 + 28 = 56$.
    *   **BFC Positioning**:
        *   Margin Collapse: $\Delta Y = \max(15, \text{margin\_top}_{\text{table}}) = \max(15, 10) = 15$.
        *   $y_{\text{table}} = 96 + 15 = 111$.
        *   **Table Fragment**: `Rect(x: 0, y: 111, w: 56, h: 56)`.
    *   **TFC Cell Positioning (Page Coordinates)**:
        *   Row 0 (`<tr>`): `Rect(x: 0, y: 111, w: 56, h: 28)`
            *   Cell (0,0) `<th>H1</th>`: `Rect(x: 0, y: 111, w: 28, h: 28)`
            *   Cell (0,1) `<th>H2</th>`: `Rect(x: 28, y: 111, w: 28, h: 28)`
        *   Row 1 (`<tr>`): `Rect(x: 0, y: 139, w: 56, h: 28)`
            *   Cell (1,0) `<td>D1</td>`: `Rect(x: 0, y: 139, w: 28, h: 28)`
            *   Cell (1,1) `<td>D2</td>`: `Rect(x: 28, y: 139, w: 28, h: 28)`
    *   State Update: `current_y = 111 + 56 = 167`, `prev_margin_bottom = 10`.
5.  **Root `<body>` Finalization**:
    *   Total Page Content Height = $167 + \text{prev\_margin\_bottom} = 167 + 10 = 177$.
    *   **Body Fragment**: `Rect(x: 0, y: 0, w: 800, h: 177)`.

---

### 3. Soundness Theorems

1.  **Deterministic Execution (`layout_page_deterministic`)**:
    Because all layout functions (`cascade_dom`, `build_layout_tree`, `layout_page`) are total, pure functions in Coq's Gallina without side effects or external oracle state, evaluating a page AST under identical CSS rules and viewport width always produces the exact same `PhysicalFragment` tree:
    $$\forall d\, r\, w\, f_1\, f_2,\; \text{render\_page}(d, r, w) = f_1 \land \text{render\_page}(d, r, w) = f_2 \implies f_1 = f_2$$

2.  **Non-Overlapping Table Cells (`row_cells_disjoint` & `table_rows_disjoint`)**:
    For any two distinct cells $c_1, c_2$ within the same table:
    *   If they belong to the same row $i$ at columns $j_1 < j_2$, $x(c_1) + w(c_1) \le x(c_2)$ because $x(c_2) = x(c_1) + w(c_1) + \sum_{k=j_1+1}^{j_2-1} W_{\text{col}}[k]$.
    *   If they belong to distinct rows $i_1 < i_2$, $y(c_1) + h(c_1) \le y(c_2)$ because $y(c_2) = y(c_1) + h(c_1) + \sum_{m=i_1+1}^{i_2-1} H_{\text{row}}[m]$.
    Thus, their open interior bounding rectangles are strictly disjoint:
    $$\text{disjoint\_rects}(R_1, R_2) \triangleq (x_1 + w_1 \le x_2) \lor (x_2 + w_2 \le x_1) \lor (y_1 + h_1 \le y_2) \lor (y_2 + h_2 \le y_1)$$

3.  **Vertical Stacking with Margin Collapsing (`bfc_vertical_stacking_sound`)**:
    For any two consecutive block-level siblings $B_k$ and $B_{k+1}$ laid out in the root Block Formatting Context, the top border edge of $B_{k+1}$ is positioned exactly $\max(\text{mb}_k, \text{mt}_{k+1})$ below the bottom border edge of $B_k$:
    $$y(B_{k+1}) = y(B_k) + h(B_k) + \max(\text{margin\_bottom}(B_k), \text{margin\_top}(B_{k+1}))$$

4.  **Bounding Rect Non-Negativity (`fragment_rect_non_negative`)**:
    By structural construction over `nat` (Peano natural numbers) and monotonic addition during BFC/TFC accumulation, every `Rect` $(x, y, w, h)$ in the emitted `PhysicalFragment` tree satisfies $x \ge 0 \land y \ge 0 \land w \ge 0 \land h \ge 0$, and every child's vertical offset is bounded below by its parent's origin.

