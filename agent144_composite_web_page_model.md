## 1. End-to-End Composite Page Layout Pipeline in Blink

In the Blink rendering engine (specifically within the `LayoutNG` architecture), laying out a composite web page requires orchestrating multiple specialized layout algorithms (`NGBlockLayoutAlgorithm`, `NGInlineLayoutAlgorithm`, `NGTableLayoutAlgorithm`) over an immutable input tree of `NGLayoutInputNode` objects to produce an immutable tree of `NGPhysicalFragment` nodes with resolved geometry.

### 1.1 Architectural Integration & Layout Pipeline
When laying out a composite document body (`<body>`), the `NGBlockLayoutAlgorithm` iterates over its inflow children sequentially along the block-progression axis (vertical, top-to-bottom in standard horizontal-tb writing mode). It maintains a running state that tracks:
*   `current_y`: The current block-axis offset relative to the container's content-box origin.
*   `prev_margin_bottom`: The bottom margin of the immediately preceding block-level sibling, preserved in an `NGMarginStrut` to resolve adjacent vertical margin collapsing before placing the next child.
*   `list_counter`: The implicit or explicit DOM counter state for `<ol>` and `<ul>` list item marker generation.

#### Headers (`<h1>`, `<h2>`) and Margin Collapsing
Headers are block-level elements processed via `NGBlockLayoutAlgorithm`. Before determining the border-box `y` coordinate of an `<h1>` or `<h2>` (and similarly for `<p>`, `<ol>`, `<ul>`, and `<table>`), Blink collapses its `margin-top` with the accumulated `prev_margin_bottom` sitting in the parent's `NGMarginStrut`.
For non-negative margins, the collapsed margin displacement is:
$$\Delta_{\text{margin}} = \max(M_{\text{prev\_bottom}}, M_{\text{curr\_top}})$$
For the very first inflow child of the root container (where no preceding sibling exists), no collapse occurs with a sibling, and the initial offset is governed directly by the parent's top border, top padding, and the child's `margin-top`:
$$Y_{\text{first}} = Y_{\text{parent\_content}} + M_{\text{first\_top}}$$
For all subsequent siblings $i > 0$:
$$Y_{i} = (Y_{i-1} + H_{\text{border\_box}, i-1}) + \max(M_{\text{bottom}, i-1}, M_{\text{top}, i})$$

#### Paragraphs (`<p>`) with Text Runs and Inline Spacing
Paragraphs establish an Inline Formatting Context (IFC) executed by `NGInlineLayoutAlgorithm`. Text content is segmented into atomic inline runs (`NGInlineItem`). Each text run carries an intrinsic advance width and line height, plus an inline spacing parameter (`word-spacing` / inter-run gap).
Given a sequence of $k$ text runs $R_1, \dots, R_k$ on a single line with widths $w_j$, heights $h_j$, and inter-run spacing $s$:
*   Each run $j$ is positioned horizontally at $X_j = X_{\text{content}} + \sum_{m=1}^{j-1} (w_m + s)$.
*   The total intrinsic content height of the paragraph is the maximum line height of its constituent runs:
    $$H_{\text{content}}(\text{p}) = \max_{1 \le j \le k} (h_j)$$

#### Lists (`<ol>`, `<ul>`, `<li>`) and Counter Progression
List containers (`<ol>`, `<ul>`) are block boxes that indent their content area (modeled via `padding-left` or `margin-left`) and initialize a counter state. Each child `<li>` generates a principal block box and an associated marker box (`LayoutNGListItem` / `LayoutNGOutsideListMarker`).
*   In an ordered list (`<ol>`), an internal integer counter $c$ starts at $1$ and increments monotonically ($c_{n} = c_{n-1} + 1$) for each `<li>` child.
*   In an unordered list (`<ul>`), the marker index is fixed at $0$ (representing a static bullet glyph).
*   Within the list container, consecutive `<li>` elements participate in standard block-axis margin collapsing with one another using the same $\max(M_{\text{prev\_bottom}}, M_{\text{curr\_top}})$ rule.

#### Tables (`<table>`, `<tr>`, `<td>`) with Separated Borders
Under `border-collapse: separate`, `NGTableLayoutAlgorithm` computes column widths and row heights across a 2D grid:
*   The table container has its own `border`, `padding`, and `border_spacing` ($S$).
*   Inside the table's content box, rows (`<tr>`) are stacked vertically, separated by $S$ (with $S$ also applied before the first row and after the last row).
*   Inside each row, cells (`<td>`) are placed horizontally from left to right, separated by $S$ (with $S$ applied before the first cell and after the last cell).
*   Each cell resolves its own box model (`border`, `padding`, `box-sizing`) around its intrinsic content width and height.
*   The height of a row is the maximum border-box height among all cells in that row:
    $$H_{\text{row}} = \max_{c \in \text{cells}} H_{\text{border\_box}}(c)$$
*   The total intrinsic content height of the table is the sum of all row heights plus $(N_{\text{rows}} + 1) \cdot S$.

#### CSS `box-sizing` (`content-box` vs. `border-box`), Borders, and Padding
Every layout box carries edge thicknesses for `margin` ($M_T, M_R, M_B, M_L$), `border` ($B_T, B_R, B_B, B_L$), and `padding` ($P_T, P_R, P_B, P_L$). Let $B_{H} = B_L + B_R$, $P_{H} = P_L + P_R$, $B_{V} = B_T + B_B$, and $P_{V} = P_T + P_B$.

1.  **`content-box` (Default CSS2.1 behavior):**
    Specified `width` ($W_{\text{spec}}$) and `height` ($H_{\text{spec}}$) apply strictly to the content area.
    $$W_{\text{border\_box}} = W_{\text{content}} + P_H + B_H$$
    $$H_{\text{border\_box}} = H_{\text{content}} + P_V + B_V$$

2.  **`border-box`:**
    Specified dimensions define the outer border box directly (clamped below by $P+B$ so content dimensions remain non-negative).
    $$W_{\text{border\_box}} = \max(W_{\text{spec}}, P_H + B_H), \quad W_{\text{content}} = W_{\text{border\_box}} - (P_H + B_H)$$
    $$H_{\text{border\_box}} = \max(H_{\text{spec}}, P_V + B_V), \quad H_{\text{content}} = H_{\text{border\_box}} - (P_V + B_V)$$

---

## 2. Concrete Evaluation of a Composite Web Page

We evaluate a complete composite HTML document inside an $800\text{px}$ root `<body>` container (`ContentBox`, `width = 800`, `padding = 10` on all sides, `border = 0`, `margin = 0`). The root content area starts at $(X_0, Y_0) = (10, 10)$.

| Element | Box Sizing | Specified $W \times H$ / Intrinsic | Margin $(T, R, B, L)$ | Border $(T, R, B, L)$ | Padding $(T, R, B, L)$ | Resolved Border-Box $(x, y, w, h)$ |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`<body>` (Root)** | `ContentBox` | $W=800$, $H=\text{auto}$ | $(0, 0, 0, 0)$ | $(0, 0, 0, 0)$ | $(10, 10, 10, 10)$ | $(0, 0, 820, 344)$ |
| **1. `<h1>`** | `BorderBox` | $W=800, H=50$ | $(10, 0, 20, 0)$ | $(0, 0, 2, 0)$ | $(4, 4, 4, 4)$ | $(10, 20, 800, 50)$ |
| **2. `<p>`** (2 runs) | `ContentBox` | Runs: $120\!\times\!20, 180\!\times\!20$ ($s=5$) | $(15, 0, 15, 0)$ | $(1, 1, 1, 1)$ | $(5, 5, 5, 5)$ | $(10, 90, 792, 32)$ |
| **3. `<h2>`** | `ContentBox` | $W=780, H=30$ | $(25, 0, 10, 0)$ | $(0, 0, 0, 0)$ | $(2, 0, 2, 0)$ | $(10, 147, 780, 34)$ |
| **4. `<ol>`** (2 `<li>`s) | `ContentBox` | $W=760$, `<li>`s: $H=20$ | $(12, 0, 18, 0)$ | $(1, 1, 1, 1)$ | $(4, 4, 4, 24)$ | $(10, 193, 790, 58)$ |
| $\quad\hookrightarrow$ `<li> #1` | `ContentBox` | $W=730, H=20$, idx $=1$ | $(0, 0, 6, 0)$ | $(0, 0, 0, 0)$ | $(1, 1, 1, 1)$ | $(35, 198, 732, 22)$ |
| $\quad\hookrightarrow$ `<li> #2` | `ContentBox` | $W=730, H=20$, idx $=2$ | $(4, 0, 0, 0)$ | $(0, 0, 0, 0)$ | $(1, 1, 1, 1)$ | $(35, 226, 732, 22)$ |
| **5. `<table>`** | `BorderBox` | $S=4$, 1 row, 2 cells | $(20, 0, 10, 0)$ | $(2, 2, 2, 2)$ | $(4, 4, 4, 4)$ | $(10, 271, 256, 53)$ |
| $\quad\hookrightarrow$ `<tr> #1` | — | 2 cells: $100\!\times\!25, 120\!\times\!25$ | — | — | — | $(16, 281, 244, 33)$ |
| $\quad\quad\hookrightarrow$ `<td> #1` | `ContentBox` | $100 \times 25$ | $(0,0,0,0)$ | $(1,1,1,1)$ | $(3,3,3,3)$ | $(20, 281, 108, 33)$ |
| $\quad\quad\hookrightarrow$ `<td> #2` | `ContentBox` | $120 \times 25$ | $(0,0,0,0)$ | $(1,1,1,1)$ | $(3,3,3,3)$ | $(132, 281, 128, 33)$ |

### Step-by-Step Coordinate Derivation
1.  **`<h1>`:** First child in `<body>`. Content top is $Y_0 = 10$. With $M_{\text{top}} = 10$, $y_1 = 10 + 10 = 20$. Because it uses `BorderBox` with specified $800 \times 50$, its border box is $(10, 20, 800, 50)$. Bottom edge is $20 + 50 = 70$. $M_{\text{prev\_bottom}} = 20$.
2.  **`<p>`:** Collapses $M_{\text{prev\_bottom}} = 20$ with $M_{\text{top}} = 15 \implies \max(20, 15) = 20$. Thus $y_2 = 70 + 20 = 90$. Its two text runs have height $20$, so content height is $20$. With `ContentBox`, $P_V = 10$, $B_V = 2$, total height $h_2 = 20 + 10 + 2 = 32$. Bottom edge is $90 + 32 = 122$. $M_{\text{prev\_bottom}} = 15$.
3.  **`<h2>`:** Collapses $M_{\text{prev\_bottom}} = 15$ with $M_{\text{top}} = 25 \implies \max(15, 25) = 25$. Thus $y_3 = 122 + 25 = 147$. With `ContentBox`, $H=30$, $P_V=4$, $B_V=0 \implies h_3 = 34$. Bottom edge is $147 + 34 = 181$. $M_{\text{prev\_bottom}} = 10$.
4.  **`<ol>`:** Collapses $M_{\text{prev\_bottom}} = 10$ with $M_{\text{top}} = 12 \implies \max(10, 12) = 12$. Thus $y_4 = 181 + 12 = 193$. Its content area starts at $x = 10 + 1 + 24 = 35$, $y = 193 + 1 + 4 = 198$.
    *   `<li> #1`: Placed at $(35, 198)$ with $h = 20 + 2 = 22$, counter $= 1$. Bottom $= 220$, $M_{\text{bottom}} = 6$.
    *   `<li> #2`: Margin collapse $\max(6, 4) = 6 \implies y = 220 + 6 = 226$, $h = 22$, counter $= 2$. Bottom $= 248$.
    *   Total `<ol>` content height $= (22 + 6 + 22) = 50$. With $P_V = 8, B_V = 2$, $h_4 = 58$. Bottom edge is $1