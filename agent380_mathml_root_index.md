**AUDIT REPORT: Blink MathML `<mroot>` Index Positioning**
**Auditor:** Agent 380
**Component:** `Blink>MathML` (Specifically `NGMathRadicalLayoutAlgorithm` and `MathMLPaintInfo`)
**Subject:** Radical Notch Coordinate Bounds and Index Offset Calculation

---

### 1. Executive Summary
In Blink’s LayoutNG implementation for MathML, the `<mroot>` element consists of two child boxes: the **base** (radicand) and the **index** (degree). The index is positioned dynamically within the "notch" (the V-shaped pocket of the radical symbol) based on metrics extracted from the font's OpenType `MATH` table, falling back to heuristic constants if the table is absent. 

Below is the technical breakdown of the notch coordinate bounds and how the index box is anchored within the layout coordinate space.

---

### 2. Relevant OpenType `MATH` Constants
Blink queries `HarfBuzzFace` to extract the following parameters from the active math font’s `MathConstants` subtable to define the notch geometry:

1. **`RadicalDegreeBottomRaisePercent` ($P_{raise}$):** Percentage of the radical's total height by which the bottom of the index is raised.
2. **`RadicalKernBeforeDegree` ($K_{before}$):** Horizontal kerning applied before the index box (left margin).
3. **`RadicalKernAfterDegree` ($K_{after}$):** Horizontal kerning applied after the index box (typically negative, pulling the index into the notch over the radical's diagonal upstroke).

---

### 3. Coordinate Space & Bounds Calculation
Blink uses a physical/logical coordinate system where $(0,0)$ is the top-left of the `<mroot>` container fragment, and $Y$ increases downwards.

#### A. Vertical Bounds (Y-Axis)
First, the radical symbol itself is sized and positioned relative to the base.
* Let $A_{rad}$ and $D_{rad}$ be the ascent and descent of the stretched/selected radical glyph.
* The total height of the radical is $H_{rad} = A_{rad} + D_{rad}$.
* The bottom of the radical sits at $Y_{rad\_bottom} = A_{container} + D_{rad}$ (where $A_{container}$ is the final baseline of the `<mroot>` element).

**The Notch Baseline Floor ($B_{notch}$):**
The vertical threshold for the bottom of the index box is calculated as a ratio of the radical's total height:
$$\Delta Y_{raise} = H_{rad} \times \left(\frac{P_{raise}}{100}\right)$$

The baseline of the index ($Y_{index\_baseline}$) is positioned such that the bottom of the index box (its descent, $D_{index}$) sits at $\Delta Y_{raise}$ above the bottom of the radical:
$$Y_{index\_baseline} = Y_{rad\_bottom} - \Delta Y_{raise} - D_{index}$$

**Vertical Bounds of the Index Box:**
* **Top Bound ($Y_{min}$):** $Y_{index\_baseline} - A_{index}$
* **Bottom Bound ($Y_{max}$):** $Y_{index\_baseline} + D_{index}$

*Audit Note:* If $Y_{min} < 0$, the index protrudes above the radical symbol. Blink handles this by expanding the `<mroot>` container's overall ascent ($A_{container}$) by $\max(0, A_{index} + D_{index} + \Delta Y_{raise} - H_{rad})$.

#### B. Horizontal Bounds (X-Axis)
The horizontal positioning of the notch relies on interleaving the index box and the radical glyph's bounding box via kerning values.

* Let $W_{index}$ be the inline-size (width) of the formatted index box.
* Let $W_{rad}$ be the inline-size of the radical glyph.

**Index Box X-Coordinates:**
1. The index is offset from the inline-start of the `<mroot>` container by $K_{before}$. Because $K_{before}$ can occasionally be negative, Blink clamps the leading space to prevent bleeding out of the container:
   $$X_{index\_start} = \max(0, K_{before})$$
2. **Right Bound of Index ($X_{index\_end}$):**
   $$X_{index\_end} = X_{index\_start} + W_{index}$$

**Radical Glyph X-Coordinates (The Notch Intersection):**
The radical symbol is placed immediately after the index, shifted by $K_{after}$ (which is negative in standard math fonts like Latin Modern Math or STIX Two Math):
$$X_{rad\_start} = X_{index\_end} + K_{after}$$

To prevent the radical symbol from protruding to the left of the container if the index is extremely narrow and $K_{after}$ is aggressively negative, Blink normalizes the start coordinates:
* Let $\text{Shift} = \min(0, K_{before}, W_{index} + K_{before} + K_{after})$
* Final $X_{index\_start} = K_{before} - \text{Shift}$
* Final $X_{rad\_start} = X_{index\_start} + W_{index} + K_{after}$

---

### 4. Fallback Heuristics (Missing `MATH` Table)
If the web author uses a standard system font lacking an OpenType `MATH` table, Blink's `MathMLStyle` / layout algorithm falls back to hard-coded CSS/MathML Core specification defaults:
* $P_{raise} = 60\%$
* $K_{before} = \frac{5}{18}\text{em} \approx 0.277\text{em}$
* $K_{after} = -\frac{10}{18}\text{em} \approx -0.555\text{em}$

---

### 5. Edge Cases & Audit Vulnerabilities
During code review of `ng_math_radical_layout_algorithm.cc`, Agent 380 notes the following boundary conditions:
1. **RTL (Right-to-Left) Directionality:** In `dir="rtl"`, the horizontal bounds are mirrored across the container's inline-size. $K_{before}$ applies to the right of the index, and $K_{after}$ pulls the radical rightward into the index.
2. **Zero-Width Index:** If the `<mroot>` is passed an empty `<mrow>` as the index, $W_{index} = 0$. The negative $K_{after}$ will pull $X_{rad\_start}$ to the left of $X_{index\_start}$, which is safely absorbed by the $\text{Shift}$ normalization logic, preventing negative container overflow.
3. **ScriptLevel Scaling:** The index child automatically receives `math-depth: add(2)` (or `scriptlevel="+2"`), scaling its font size down (typically to $0.71 \times 0.71 \approx 50\%$) *before* $W_{index}$, $A_{index}$, and $D_{index}$ are measured for the notch bounds. Note that $K_{before}$ and $K_{after}$ are read from the *parent's* font size metrics, not the scaled index font metrics.

**Status:** Bounds verified against MathML Core W3C Specification (Section 3.3.4.2). Ready for layout test validation.