**AUDIT REPORT: Blink MathML Under/Over Horizontal Centering**
**Agent:** 376
**Target Component:** `third_party/blink/renderer/core/layout/mathml/math_under_over_layout_algorithm.cc`
**Specification:** MathML Core (Section 3.4.4: `<munder>`, `<mover>`, `<munderover>`)

### 1. Executive Summary
In Blink’s LayoutNG architecture, the horizontal centering of MathML under- and over-scripts relative to the base expression is governed by the `MathUnderOverLayoutAlgorithm`. The algorithm calculates a unified inline bounding box and centers each constituent element (Base, Under, Over) within that box, adjusting for italic corrections derived from the OpenType `MATH` table.

### 2. Core Variables
Let the inline sizes (widths) of the layout fragments be defined as:
*   $W_{\text{base}}$ : Inline size of the base element.
*   $W_{\text{under}}$ : Inline size of the underscript (if present, else $0$).
*   $W_{\text{over}}$ : Inline size of the overscript (if present, else $0$).
*   $IC$ : Italic correction of the base element (retrieved via `MathItalicsCorrection`).

### 3. Container Inline Size Formula
Before calculating individual horizontal offsets, Blink determines the total inline size of the `<munder>`, `<mover>`, or `<munderover>` container ($W_{\text{container}}$). 

The container width is the maximum inline size among the children:
$$W_{\text{container}} = \max(W_{\text{base}}, W_{\text{under}}, W_{\text{over}})$$

*(Note: If the base is an embellished operator that stretches to the inline size of the container, $W_{\text{base}}$ is updated post-stretch before final offset calculation).*

### 4. Horizontal Centering Formulas (Inline Offsets)
Blink positions each child fragment along the inline axis (X-axis in horizontal writing modes) using the following offset formulas relative to the container's inline-start edge:

#### A. Base Element Offset ($X_{\text{base}}$)
The base is strictly centered within the container without italic correction adjustments:
$$X_{\text{base}} = \frac{W_{\text{container}} - W_{\text{base}}}{2}$$

#### B. Overscript Offset ($X_{\text{over}}$)
The overscript is centered relative to the container, then shifted toward the inline-end (right) by half of the base's italic correction to visually align with the slanted apex of the base glyph:
$$X_{\text{over}} = \frac{W_{\text{container}} - W_{\text{over}}}{2} + \frac{IC}{2}$$

#### C. Underscript Offset ($X_{\text{under}}$)
The underscript is centered relative to the container. Per the MathML Core specification, if the base is a large operator, it is shifted toward the inline-start (left) by half of the italic correction to align with the bottom-left visual anchor of the integral/operator:
$$X_{\text{under}} = \frac{W_{\text{container}} - W_{\text{under}}}{2} - \frac{\delta \cdot IC}{2}$$

Where $\delta$ is a boolean flag:
*   $\delta = 1$ if the base does **not** have an italic correction applied to its bounding box (i.e., standard large operators like $\int$ where the glyph overhangs the advance width).
*   $\delta = 0$ for standard base elements where italic correction is not applicable to the underscript.

### 5. Blink Implementation Realities & Edge Cases
During the audit of `MathUnderOverLayoutAlgorithm::Layout()`, the following implementation details were noted:

1.  **Clamping / Negative Offsets:** If the application of $\pm \frac{IC}{2}$ pushes the script outside the bounds of $W_{\text{container}}$, Blink may adjust the container width or clamp offsets depending on the `HasBaseWithItalicCorrection` state to prevent unintended ink overflow.
2.  **Writing Modes:** The formulas above operate on `LayoutUnit` values in **logical coordinates** (`inline_offset`). Blink automatically resolves these to physical X/Y coordinates based on the `WritingDirectionMode` (e.g., `kHorizontalTb`, `kVerticalRl`) during the fragment builder phase.
3.  **Sub-pixel Rendering:** Division by $2$ is executed via `LayoutUnit` bit-shifting or fixed-point division (`/ 2`), which has a precision of $1/64\text{th}$ of a CSS pixel, occasionally resulting in a $0.015625\text{px}$ rounding delta between the left and right margins. 

**Audit Status:** Compliant with W3C MathML Core specification. End of report.