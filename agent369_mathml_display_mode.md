**AGENT 369 — AUDIT REPORT: BLINK MATHML CORE**
**Subject:** Layout Constraints: Block (`display="block"`) vs. Inline (`display="inline"`) Math
**Architecture:** Blink LayoutNG

---

### 1. CSS Box Generation & Flow Participation
In Blink’s LayoutNG engine, the `<math>` root element's layout behavior is primarily governed by the user-agent stylesheet mapping of the `display` attribute to the CSS `display` property, handled via `NGMathRowLayoutAlgorithm` and `NGBlockNode`.

*   **Inline Math (`display="inline"` / default):**
    *   **CSS Property:** `display: inline math;`
    *   **Formatting Context:** Generates an inline-level atomic box that participates in the parent’s **Inline Formatting Context (IFC)** via `NGInlineLayoutAlgorithm`. 
    *   **Line Breaking:** Treated as an atomic inline; line breaking *inside* the `<math>` root is suppressed by default in MathML Core, though the box itself wraps with surrounding text lines.
    *   **Baseline Alignment:** Aligns its internal mathematical axis/alphabetic baseline with the surrounding text line box baseline.

*   **Block Math (`display="block"`):**
    *   **CSS Property:** `display: block math;`
    *   **Formatting Context:** Generates a block-level box participating in a **Block Formatting Context (BFC)**.
    *   **Box Geometry:** Takes up the full available inline-size of its containing block (`width: auto` resolves to `100%` of the parent's content box).
    *   **Alignment:** Contents are horizontally centered within the block container by default. The UA stylesheet applies `margin-block: 1em` (or equivalent structural spacing depending on context), isolating it from adjacent inline flows.

---

### 2. Typographic & OpenType `MATH` Table Constraints
The `<math>` element initializes two critical CSS properties that cascade down the DOM tree: `math-style` and `math-shift`. These dictate how Blink queries the OpenType `MATH` table via HarfBuzz.

#### A. `math-style` (`normal` vs. `compact`)
*   **Block Math (`math-style: normal`):**
    *   **Fractions (`<mfrac>`):** Uses `FractionNumeratorDisplayStyleShiftUp` and `FractionDenominatorDisplayStyleShiftDown`. Numerator and denominator remain at current `math-depth` (font size is maintained unless nested).
    *   **Large Operators (`<mo>`):** Queries the `MATH` table's `DisplayOperatorMinHeight` constant. HarfBuzz selects larger glyph variants or assembles glyphs (e.g., $\sum, \int$) to meet this threshold.
    *   **Limits (`<munderover>`, `<munder>`, `<mover>`):** Movable limits on operators (where `movablelimits="true"`) are rendered strictly as **under-over** scripts (`NGMathUnderOverLayoutAlgorithm`).
*   **Inline Math (`math-style: compact`):**
    *   **Fractions (`<mfrac>`):** Uses standard `FractionNumeratorShiftUp` and `FractionDenominatorShiftDown` to minimize line-box height disruption. Increments `math-depth` by 1 for children, shrinking their `font-size` to `71%` (via `scriptPercentScaleDown`).
    *   **Large Operators (`<mo>`):** Renders at base glyph size (or a smaller inline variant) to prevent excessive line-height expansion in the parent IFC.
    *   **Limits:** Movable limits on operators are converted from under-over layout to **sub-sup** layout (`NGMathScriptsLayoutAlgorithm`), shifting limits to the right of the base glyph to conserve vertical space.

#### B. `math-shift` (`normal` vs. `compact`)
*   **Block Math:** Preserves `math-shift: normal`. Superscripts (`<msup>`, `<msubsup>`) shift upward using the standard `SuperscriptShiftUp` OpenType constant.
*   **Inline Math:** Sets `math-shift: compact` (often referred to as "cramped" style in TeX). Superscripts use `SuperscriptShiftUpCramped`, reducing the vertical ascent of the script box to prevent collisions with the previous text line's descent.

---

### 3. Box Metrics & Intrinsic Sizing (LayoutNG)
During the `ComputeMinMaxSizes` and `Layout` phases in Blink:

*   **Inline Math:**
    *   **Ascent/Descent:** The calculated ascent and descent of the `<math>` box directly inflate the containing `NGLineBox`. Excessive vertical growth (e.g., nested inline fractions) degrades typographic rhythm.
    *   **Horizontal Sizing:** Shrink-to-fit based on the sum of the inline-sizes of its children (`MinMaxSizes` max-content).

*   **Block Math:**
    *   **Ascent/Descent:** Unconstrained by surrounding text lines. Vertical bounds expand freely based on the aggregated heights of child `NGLayoutResult` objects.
    *   **Horizontal Sizing:** The outer box fills the available inline space, while an anonymous internal centering mechanism positions the mathematical content's `max-content` width at the horizontal midpoint: $\text{Offset}_{\text{inline}} = \max\left(0, \frac{\text{AvailableInlineSize} - \text{ContentInlineSize}}{2}\right)$.

---

### 4. Summary Matrix

| Constraint / Feature | Inline Math (`display="inline"`) | Block Math (`display="block"`) |
| :--- | :--- | :--- |
| **CSS Display** | `inline math` | `block math` |
| **Formatting Context** | Inline (IFC) | Block (BFC) |
| **Default `math-style`** | `compact` | `normal` |
| **Default `math-shift`** | `compact` (cramped) | `normal` |
| **`movablelimits` Behavior**| Shifts to `<msubsup>` (`NGMathScripts`) | Remains `<munderover>` (`NGMathUnderOver`) |
| **Operator Sizing** | Base glyph / Inline variant | Minimum height = `DisplayOperatorMinHeight` |
| **Fraction Child Depth** | `math-depth: add(1)` (scales font down) | `math-depth: +0` (preserves font size) |
| **Horizontal Allocation** | Shrink-to-fit (`max-content`) | `100%` of container (content centered) |

**Audit Status:** Compliant with W3C MathML Core specification. LayoutNG pipeline metrics verified. 
**Agent 369 signing off.**