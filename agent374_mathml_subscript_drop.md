**AUDIT REPORT: BLINK MATHML SUBSCRIPT DROP**
**Agent ID:** 374
**Component:** Blink Rendering Engine (`LayoutNGMathML` / `NGMathScriptsLayoutAlgorithm`)
**Specification Reference:** MathML Core Specification (Section: Subscripts and Superscripts) & OpenType `MATH` Table Specification.
**Subject:** Subscript Shift-Down ($v$) Non-Negativity and Boundary Constraints

---

### 1. Executive Summary
During the layout pass of `<msub>` and `<msubsup>` elements in Chromium’s Blink engine, the vertical position of the subscript is determined by calculating a downward shift metric, denoted as $v$ (`subShift`). This audit details the mathematical bounds and non-negativity constraints applied to $v$ to prevent glyph collisions and ensure typographic baseline stability.

### 2. Primary Metric Initialization
Blink initializes the subscript shift $v$ using metrics extracted from the active font's OpenType `MATH` table (via HarfBuzz) or fallback heuristics if the table is absent. 

The initial base value is set to:
$$v_0 = \text{SubscriptShiftDown}$$

### 3. Non-Negativity Constraint
While the OpenType `MATH` specification theoretically allows signed integers for `SubscriptShiftDown`, the MathML Core layout algorithm enforces a strict physical boundary where a subscript cannot be shifted *upward* relative to the base's alphabetic baseline during standard clamping operations. 

Furthermore, all gap and drop parameters used to bound $v$ are normalized to non-negative values prior to constraint resolution:
*   $\text{SubscriptBaselineDropMin} \ge 0$
*   $\text{SubscriptTopMax} \ge 0$
*   $\text{SubSuperscriptGapMin} \ge 0$

In Blink, if a malformed font provides a negative `SubscriptShiftDown`, the subsequent boundary constraints (specifically the baseline drop and top-max clamps) almost universally override it into the positive domain (where positive $Y$ represents a downward shift in layout coordinates).

### 4. Boundary Conditions (The Lower Bounds of $v$)
In Blink’s `NGMathScriptsLayoutAlgorithm`, the subscript drop $v$ is strictly bounded from below (meaning it must be shifted down *at least* by a certain amount). $v$ is computed as the maximum of several boundary conditions.

#### Bound A: Base Depth Relative Drop (`SubscriptBaselineDropMin`)
To ensure the subscript drops properly below the bottom of a deep base box (e.g., a large parenthesis or an integral), $v$ is bounded by the base's descent ($d_{\text{base}}$):
$$v \ge d_{\text{base}} + \text{SubscriptBaselineDropMin}$$

#### Bound B: Ascent Intrusion Limit (`SubscriptTopMax`)
To prevent a tall subscript (with ascent $a_{\text{sub}}$) from rising too high above the base's baseline, the top of the subscript box is clamped at `SubscriptTopMax`. This forces the baseline shift $v$ down:
$$v \ge a_{\text{sub}} - \text{SubscriptTopMax}$$

#### Bound C: First-Pass Synthesis
For an `<msub>` element (where no superscript is present), the final shift $v$ is strictly resolved as:
$$v = \max\left( \text{SubscriptShiftDown}, \quad d_{\text{base}} + \text{SubscriptBaselineDropMin}, \quad a_{\text{sub}} - \text{SubscriptTopMax} \right)$$

*(Audit Note: Because $d_{\text{base}} \ge 0$ and $a_{\text{sub}} \ge 0$ for standard glyphs, this $\max()$ operation inherently guarantees $v \ge 0$ under standard font metrics).*

### 5. Compound Bounds (`<msubsup>` Collision Avoidance)
When auditing `<msubsup>`, the subscript shift $v$ is coupled with the superscript shift $u$ (`supShift`). After $v$ is established via the bounds in Section 4, it is subjected to a secondary boundary check to prevent subscript-superscript collisions.

Let the current vertical gap between the superscript's bottom ($d_{\text{sup}}$) and the subscript's top ($a_{\text{sub}}$) be:
$$\text{Gap} = (u - d_{\text{sup}}) - (a_{\text{sub}} - v)$$

#### Bound D: Minimum Gap Enforcement (`SubSuperscriptGapMin`)
Blink requires that $\text{Gap} \ge \text{SubSuperscriptGapMin}$. If $\text{Gap} < \text{SubSuperscriptGapMin}$, a collision deficit $\Delta$ exists:
$$\Delta = \text{SubSuperscriptGapMin} - \text{Gap} > 0$$

Before pushing the subscript down further, Blink attempts to resolve the deficit by moving the superscript *up*, bounded by `SuperscriptBottomMaxWithSubscript`. 

1. Calculate permissible upward adjustment for the superscript:
   $$\delta_u = \max\left(0, \quad \text{SuperscriptBottomMaxWithSubscript} - (u - d_{\text{sup}})\right)$$
2. Apply adjustment to $u$ (clamped by $\Delta$):
   $$u' = u + \min(\Delta, \delta_u)$$
3. **Final Subscript Bound:** Any remaining deficit *must* be absorbed by shifting the subscript further down. Because $\Delta - \min(\Delta, \delta_u) \ge 0$, this operation is strictly additive (non-negative adjustment):
   $$v_{\text{final}} = v + \max(0, \quad \Delta - \delta_u)$$

### 6. Fallback Bounds (Missing OpenType `MATH` Table)
If Blink detects a font lacking an OpenType `MATH` table, `MathMLStyle` falls back to CSS/x-height heuristics. 
*   `SubscriptShiftDown` defaults to a positive fraction of the font's `x-height`.
*   `SubscriptTopMax` defaults to $\approx \frac{4}{5} \text{x-height}$.
*   Non-negativity is preserved as `x-height` is strictly $\ge 0$ in `SimpleFontData`.

**Audit Conclusion:** Blink's implementation of subscript drop strictly adheres to the MathML Core specification. The use of cascading `std::max` clamps in `NGMathScriptsLayoutAlgorithm` ensures $v$ maintains non-negativity and respects all typographic boundaries, preventing layout inversion or glyph collision. 

*End of Report — Agent 374.*