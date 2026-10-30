**AUDIT REPORT: Blink LayoutNG – Page Margin Box Available Space Calculation**
**Agent ID:** 354
**Target Component:** `third_party/blink/renderer/core/layout/` (LayoutNG Paged Media / `@page` margin boxes)
**Objective:** Detail the algorithmic calculation of available space (main and cross axes) for the 16 CSS `@page` margin boxes according to CSS Paged Media Level 3 and Blink’s LayoutNG implementation.

---

### 1. Architectural Context & Geometry Definitions

Before computing available space for individual margin boxes, the `NGPageLayoutAlgorithm` establishes the geometry of the **Page Box** and the **Page Area** (content box).

*   $\text{Page}_{\text{W}}, \text{Page}_{\text{H}}$: Total physical width and height of the page sheet (adjusted for `@page` `size` and `orientation`).
*   $M_{\text{top}}, M_{\text{right}}, M_{\text{bottom}}, M_{\text{left}}$: The resolved physical margins of the `@page` box.
*   $\text{PageArea}_{\text{W}} = \max(0, \text{Page}_{\text{W}} - M_{\text{left}} - M_{\text{right}})$
*   $\text{PageArea}_{\text{H}} = \max(0, \text{Page}_{\text{H}} - M_{\text{top}} - M_{\text{bottom}})$

The 16 margin boxes exist within the space created by the page margins around the Page Area. They are categorized into **Corner Boxes** (4) and **Edge Boxes** (12, grouped into 4 edges of 3 boxes: $A$, $B$ [center], and $C$).

---

### 2. Cross-Axis Available Space Calculation

The "Cross-Axis" is the dimension perpendicular to the page edge associated with the margin box. Its available space is fixed and directly inherited from the corresponding `@page` margin thickness.

*   **Top Edge Boxes** (`@top-left-corner`, `@top-left`, `@top-center`, `@top-right`, `@top-right-corner`):
    $$\text{Available}_{\text{Cross}} = M_{\text{top}}$$
*   **Bottom Edge Boxes** (`@bottom-left-corner`, `@bottom-left`, `@bottom-center`, `@bottom-right`, `@bottom-right-corner`):
    $$\text{Available}_{\text{Cross}} = M_{\text{bottom}}$$
*   **Left Edge Boxes** (`@left-top`, `@left-middle`, `@left-bottom`):
    $$\text{Available}_{\text{Cross}} = M_{\text{left}}$$
*   **Right Edge Boxes** (`@right-top`, `@right-middle`, `@right-bottom`):
    $$\text{Available}_{\text{Cross}} = M_{\text{right}}$$

---

### 3. Main-Axis Available Space Calculation

The "Main-Axis" runs parallel to the associated page edge. 

#### 3.1. Corner Margin Boxes
Corner boxes have strictly deterministic available space in both dimensions, bounded by the intersecting page margins:
*   `@top-left-corner`: $\text{Width} = M_{\text{left}}$, $\text{Height} = M_{\text{top}}$
*   `@top-right-corner`: $\text{Width} = M_{\text{right}}$, $\text{Height} = M_{\text{top}}$
*   `@bottom-right-corner`: $\text{Width} = M_{\text{right}}$, $\text{Height} = M_{\text{bottom}}$
*   `@bottom-left-corner`: $\text{Width} = M_{\text{left}}$, $\text{Height} = M_{\text{bottom}}$

#### 3.2. Edge Margin Boxes (The 3-Box Resolution Algorithm)
For any given edge (Top, Bottom, Left, Right), three boxes ($A$, $B$, $C$) share a total main-axis available space ($\text{TotalMain}$).
*   For **Top / Bottom** edges: $\text{TotalMain} = \text{PageArea}_{\text{W}}$ (representing $A=\text{left}, B=\text{center}, C=\text{right}$).
*   For **Left / Right** edges: $\text{TotalMain} = \text{PageArea}_{\text{H}}$ (representing $A=\text{top}, B=\text{middle}, C=\text{bottom}$).

Because edge boxes can have `auto` sizes, their available space is dynamically resolved using the **CSS Paged Media Margin Box Variable Dimension Sizing Algorithm**. Blink implements this via intrinsic size measurement followed by constraint resolution.

##### Step 1: Intrinsic Size Collection
For each generated box $i \in \{A, B, C\}$ on an edge:
1.  If the box is not generated (`content: none` or `display: none`), its outer min-content size ($W_{\min, i}$) and max-content size ($W_{\max, i}$) are $0$.
2.  If the box has a definite computed main-axis size (e.g., `width: 100px` or `width: 20%` resolved against $\text{TotalMain}$), Blink clamps/sets its outer intrinsic sizes to that definite value (plus main-axis margins, borders, and padding).
3.  If the box has `width: auto` (or `height: auto` for vertical edges), Blink runs `ComputeMinMaxSizes` on the margin box node using an orthogonal or parallel `NGConstraintSpace` where the cross-axis is fixed to $\text{Available}_{\text{Cross}}$.
4.  **Auto Margins:** If a box has `margin: auto` in the main axis, that margin is treated as $0$ during intrinsic size calculation.

##### Step 2: Resolving `auto` Main-Axis Sizes
Blink determines the tentative outer main-axis available space for each box based on the presence of the center/middle box ($B$):

**Case 1: Center Box ($B$) has content (is generated)**
To ensure $B$ remains strictly centered on the page edge, $A$ and $C$ are paired into a synthetic "AC" construct where $W_{\min, AC} = 2 \cdot \max(W_{\min, A}, W_{\min, C})$ and $W_{\max, AC} = 2 \cdot \max(W_{\max, A}, W_{\max, C})$.
*   Blink resolves the sizes between $B$ and $AC$ against $\text{TotalMain}$ using the standard distribution rules (Detailed in Step 3).
*   Once $W_{B}$ is resolved, the remaining space for $A$ and $C$ is:
    $$\text{Available}_{\text{side}} = \frac{\text{TotalMain} - W_{B}}{2}$$
*   Both $A$ and $C$ are then individually constrained by $\text{Available}_{\text{side}}$. If $A$ has `auto` size, its resolved size is $\min(W_{\max, A}, \text{Available}_{\text{side}})$. (Same for $C$).

**Case 2: Center Box ($B$) is empty / not generated**
Boxes $A$ and $C$ compete directly for $\text{TotalMain}$. Their sizes are resolved directly against $\text{TotalMain}$ using the distribution rules (Step 3).

##### Step 3: Space Distribution Rules (Flex-like Resolution)
When resolving a set of `auto`-sized boxes (either $\{A, C\}$ or $\{B, AC\}$) against a target space $S$ (where $S = \text{TotalMain}$ minus any definite box sizes):

1.  **Unconstrained Fit ($\sum W_{\max} \le S$):**
    Every `auto` box receives its max-content size:
    $$\text{Size}_i = W_{\max, i}$$
2.  **Soft Constraint ($\sum W_{\min} \le S < \sum W_{\max}$):**
    Each box starts at $W_{\min, i}$. The remaining available space ($S - \sum W_{\min}$) is distributed proportionally based on each box's flexibility factor $(W_{\max, i} - W_{\min, i})$:
    $$\text{Size}_i = W_{\min, i} + (S - \sum W_{\min}) \times \frac{W_{\max, i} - W_{\min, i}}{\sum (W_{\max} - W_{\min})}$$
3.  **Overflow / Hard Constraint ($S < \sum W_{\min}$):**
    The boxes exceed available space even at min-content. Space is distributed proportionally to their $W_{\min, i}$:
    $$\text{Size}_i = S \times \frac{W_{\min, i}}{\sum W_{\min}}$$
    *(Note: If $\sum W_{\min} == 0$, space is divided equally).*

---

### 4. Final `NGConstraintSpace` Construction for Layout

Once the outer main-axis size ($\text{Size}_i$) and outer cross-axis size ($\text{Available}_{\text{Cross}}$) are resolved for a specific margin box, Blink constructs its final `NGConstraintSpace` to perform the actual `NGBlockNode::Layout`:

1.  **Margin Resolution:** Any `auto` margins on the margin box itself (in both main and cross axes) are resolved first by subtracting the box's border-box size from the allocated outer available space.
2.  **Available Size Assignment:**
    $$\text{ConstraintSpace}_{\text{Main}} = \max(0, \text{Size}_i - \text{Margins}_{\text{Main}})$$
    $$\text{ConstraintSpace}_{\text{Cross}} = \max(0, \text{Available}_{\text{Cross}} - \text{Margins}_{\text{Cross}})$$
3.  **Fixed Size Flags:**
    *   If the margin box's cross-axis dimension is `auto`, it behaves like a table-cell (via `vertical-align`); otherwise, it is set as a fixed size in the constraint space.
    *   The main-axis dimension in the `NGConstraintSpace` is marked as **Fixed** to the resolved $\text{ConstraintSpace}_{\text{Main}}$ value so child content wraps and aligns properly within the newly calculated boundary.

### 5. Audit Edge Cases & Quirks Noted in Blink
*   **Writing Modes:** Blink maps the physical dimensions of the margin boxes into logical dimensions (`InlineSize` and `BlockSize`) based on the **margin box's own `writing-mode`**, not the `@page` or document writing mode. Therefore, for `@left-middle` with `writing-mode: horizontal-tb`, the "Main-Axis" ($\text{PageArea}_{\text{H}}$) maps to the **Block** axis, and the "Cross-Axis" ($M_{\text{left}}$) maps to the **Inline** axis.
*   **Negative Page Areas:** If page margins exceed page dimensions, $\text{PageArea}_{\text{W/H}}$ is clamped to `LayoutUnit(0)`, collapsing the main-axis available space for edge boxes to `0px`.

**End of Audit Report.**