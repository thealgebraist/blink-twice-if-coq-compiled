**Audit Report: Blink MathML `<mtable>` Cell Baseline Alignment**
**Auditor:** Agent 383
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/layout/ng/mathml/` and `css/mathml.css`)
**Subject:** Baseline Alignment of `<mtd>` cells within `<mtr>` rows inside `<mtable>`.

---

### 1. Executive Summary
In Blink’s LayoutNG architecture, `<mtable>` is implemented by piggybacking on the standard CSS Table Layout engine (`LayoutNGTable`). While MathML Core specifies complex alignment behaviors, Blink maps `<mtable>`, `<mtr>`, and `<mtd>` to `display: table`, `display: table-row`, and `display: table-cell` respectively. 

Cell baseline alignment—how individual `<mtd>` elements align with each other horizontally across an `<mtr>`—relies on the synthesis and propagation of the **first baseline** from the MathML layout algorithms (`NGMathRowLayoutAlgorithm`, `NGMathFractionLayoutAlgorithm`, etc.) up to the `NGTableLayoutAlgorithm`.

### 2. UA Stylesheet Mapping (`mathml.css`)
According to the MathML Core specification, the default vertical alignment for table cells is `baseline`. Blink enforces this at the User Agent stylesheet level:

```css
mtable {
  display: table;
  /* ... */
}
mtr {
  display: table-row;
}
mtd {
  display: table-cell;
  vertical-align: baseline; /* Enforces baseline alignment by default */
  text-align: center;
  padding: 0.5ex 0.4em;
}
```
*Audit Note:* MathML 3 allowed the `rowalign` attribute on `<mtable>`, `<mtr>`, and `<mtd>` (with values like `top`, `bottom`, `center`, `baseline`, `axis`). **MathML Core deprecates/removes `rowalign`**. Blink strictly follows MathML Core here; native attribute mapping for `rowalign` is omitted, and alignment is strictly controlled via the CSS `vertical-align` property (defaulting to `baseline`).

### 3. Cell Baseline Determination (Inside the `<mtd>`)
An `<mtd>` acts as an implicit `<mrow>`. Therefore, its internal layout is governed by `NGMathRowLayoutAlgorithm`, even though its outer display acts as a table cell (`NGBlockNode` handled by table layout).

1. **The Math Axis vs. The Baseline:** 
   Inside a `<mtd>`, child MathML elements (like `<mfrac>`, `<msqrt>`, `<mo>`) are aligned relative to the **Math Axis** (an imaginary horizontal line above the baseline by `AxisHeight`, derived from the OpenType `MATH` table), which is then shifted to determine the final alphabetic baseline.
2. **Baseline Calculation:**
   As `NGMathRowLayoutAlgorithm` lays out the contents of the `<mtd>`, it tracks the maximum ascent (above the baseline) and descent (below the baseline) of its inline/math children.
3. **Fragment Export:**
   Once the `<mtd>` layout is complete, the algorithm calls `container_builder_.SetBaselines(baseline)`. This records the distance from the `<mtd>`’s top border-edge (including top padding) to the calculated alphabetic baseline of its internal `<mrow>`.

### 4. Row Baseline Alignment (Across the `<mtr>`)
Once individual `<mtd>` fragments are generated, `NGTableRowLayoutAlgorithm` and `NGTableSectionLayoutAlgorithm` take over to align the cells within the `<mtr>`.

1. **Querying the Baseline:**
   Because the `<mtd>` has `vertical-align: baseline`, the table row layout algorithm queries `NGBoxFragment::FirstBaseline()` on each cell in the row.
2. **Computing the Row Baseline:**
   The row algorithm calculates the **Row Baseline** by finding the maximum baseline offset among all baseline-aligned `<mtd>` cells in that `<mtr>`:
   $$\text{RowBaseline} = \max_{i \in \text{cells}} (\text{Cell}_i\text{.FirstBaseline}())$$
3. **Shifting the Cells:**
   For each cell $i$, the algorithm applies a vertical physical offset (effectively an internal top-margin shift within the row) equal to:
   $$\text{Offset}_i = \text{RowBaseline} - \text{Cell}_i\text{.FirstBaseline}()$$
   This guarantees that the internal mathematical baselines of all `<mtd>` elements in the row form a single, continuous horizontal line.
4. **Row Height Finalization:**
   The final height of the `<mtr>` is then computed as the maximum of the `RowBaseline` plus the largest descent among the baseline-aligned cells, compared against the total height of any non-baseline aligned cells (if `vertical-align` was overridden via CSS).

### 5. Interaction with `<mtable>` Baseline
While this audit focuses on *cell* baseline alignment, it directly impacts the `<mtable>`'s own baseline in the surrounding math expression:
* The `<mtr>` exports its calculated `RowBaseline` to the `<mtable>`.
* By default in MathML Core, an `<mtable>` aligns its own center/axis with the surrounding math axis. However, if CSS `vertical-align: baseline` is applied to the `<mtable>`, Blink uses the exported `RowBaseline` of the **first `<mtr>`** as the baseline of the entire `<mtable>`.

### 6. Known Edge Cases & Audit Findings
* **Empty `<mtd>` Cells:** If an `<mtd>` is completely empty, `NGMathRowLayoutAlgorithm` may not produce a content-based baseline. Blink falls back to synthesizing the baseline at the bottom of the content box (before bottom padding), which causes the bottom of the empty cell to align with the text baseline of adjacent cells.
* **Multiline Content inside `<mtd>`:** If an `<mtd>` contains standard HTML blocks (e.g., `<div>` or `<p>`), it still exports the *first* baseline (`kFirstBaseline`), maintaining consistency with CSS 2.1 table specifications.
* **Legacy MathML3 `rowalign` Failure:** Content relying on `<mtable rowalign="top">` will fail to align to the top in Blink, falling back to `baseline` alignment unless migrated to `<mtd style="vertical-align: top">`. This is **Working As Intended (WAI)** per MathML Core, though it remains a common interoperability friction point with legacy MathML content.

**Status:** Compliant with W3C MathML Core Specification. 
**Sign-off:** Agent 383.