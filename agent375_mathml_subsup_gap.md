**AUDIT REPORT: Blink MathML `<msubsup>` Script Gap Clearance**  
**Auditor:** Agent 375  
**Component:** `Blink>MathML` (`NGMathScriptsLayoutAlgorithm`)  
**Specification Reference:** MathML Core Specification (Section 3.4.3.2: Subscript and Superscript / `<msubsup>`)

---

### 1. Executive Summary
This audit details the layout constraints and collision-avoidance mechanisms implemented in Blink’s LayoutNG engine to guarantee non-overlap between the subscript and superscript children of a `<msubsup>` element. 

Blink resolves script placement in a two-phase vertical pass: **Initial Independent Positioning** followed by **Collision Resolution (Gap Clearance)**.

---

### 2. Relevant OpenType MATH Constants
Blink queries `OpenTypeMathSupport` to extract metrics from the active font's `MATH` table. If the font lacks a `MATH` table, fallback heuristics based on standard font metrics (e.g., `x-height`, `em`) are used. 

For `<msubsup>` gap clearance, the following parameters are critical:
*   **$v_{\text{min}}$ (`SubSuperscriptGapMin`):** The minimum vertical gap allowed between the ink boxes of the subscript and the superscript.
*   **$u_{\text{max}}$ (`SuperscriptBottomMaxWithSubscript`):** The maximum allowed level for the bottom of the superscript relative to the baseline when a subscript is present.
*   $u_0$ (`SuperscriptShiftUp` / `SuperscriptShiftUpCramped`): Initial upward shift of the superscript.
*   $d_0$ (`SubscriptShiftDown`): Initial downward shift of the subscript.

---

### 3. Phase 1: Initial Baseline Shifts
Before checking for overlap, Blink calculates the preliminary vertical shifts from the base's baseline:
1.  **Superscript Shift ($u$):** Determined by the maximum of the font’s `SuperscriptShiftUp` (or cramped variant), the base’s `SuperscriptBaselineDropMax`, and the superscript’s `SuperscriptBottomMin`.
2.  **Subscript Shift ($d$):** Determined by the maximum of the font’s `SubscriptShiftDown`, the base’s `SubscriptBaselineDropMin`, and the subscript’s `SubscriptTopMax`.

---

### 4. Phase 2: Non-Overlap & Gap Clearance Algorithm
Once initial $u$ (upward) and $d$ (downward) shifts are established, `NGMathScriptsLayoutAlgorithm` executes the gap clearance logic to ensure the superscript’s descent and the subscript’s ascent do not collide.

Let:
*   $D_{\text{sup}}$ = Descent of the superscript box (distance from its baseline to its bottom edge).
*   $A_{\text{sub}}$ = Ascent of the subscript box (distance from its baseline to its top edge).

#### Step 4.1: Current Gap Calculation
Blink calculates the actual vertical clearance ($G_{\text{current}}$) between the bottom of the superscript and the top of the subscript:
$$G_{\text{current}} = (u - D_{\text{sup}}) + (d - A_{\text{sub}})$$

If $G_{\text{current}} \ge v_{\text{min}}$ (`SubSuperscriptGapMin`), no overlap exists, and the minimum gap requirement is already satisfied. The algorithm terminates here.

#### Step 4.2: Primary Adjustment (Pushing the Superscript Up)
If $G_{\text{current}} < v_{\text{min}}$, a collision or insufficient gap is detected. Blink attempts to resolve this first by moving the **superscript upward**, up to a defined threshold.

The specification dictates that the bottom of the superscript should ideally not be pushed higher than $u_{\text{max}}$ (`SuperscriptBottomMaxWithSubscript`) unless forced. Blink calculates the maximum allowable adjustment ($\Delta u$) to the superscript before hitting this ceiling:
$$\Delta u = u_{\text{max}} - (u - D_{\text{sup}})$$

If $\Delta u > 0$:
*   Blink adjusts the superscript upward by $\min(v_{\text{min}} - G_{\text{current}}, \Delta u)$.
*   $$u_{\text{new}} = u + \min(v_{\text{min}} - G_{\text{current}}, \Delta u)$$
*   The current gap $G_{\text{current}}$ is recalculated using $u_{\text{new}}$.

#### Step 4.3: Secondary Adjustment (Pushing the Subscript Down)
If the gap is *still* insufficient ($G_{\text{current}} < v_{\text{min}}$) after the superscript has reached its $u_{\text{max}}$ ceiling (or if it started above it), the remaining deficit **must** be absorbed by pushing the **subscript downward**.

$$\Delta d = v_{\text{min}} - G_{\text{current}}$$
$$d_{\text{new}} = d + \Delta d$$

---

### 5. Blink Implementation Specifics & Edge Cases

1.  **LayoutUnit Precision:** 
    In `ng_math_scripts_layout_algorithm.cc`, all metric calculations use `LayoutUnit` (fixed-point 1/64th pixel precision). Subpixel rounding of `SubSuperscriptGapMin` can occasionally result in a 1-subpixel variance compared to floating-point reference implementations, though visually imperceptible.
2.  **Fallback Heuristics (Non-MATH Fonts):**
    If a web developer uses a system font without an OpenType `MATH` table (e.g., Arial), Blink falls back to `SubSuperscriptGapMin = 4 * RuleThickness` (where `RuleThickness` defaults to roughly $0.05\text{em}$). `SuperscriptBottomMaxWithSubscript` falls back to $\frac{4}{5}$ of the font's `x-height`.
3.  **Zero-Height / Empty Scripts:**
    If either the `<msubsup>` subscript or superscript is an empty `<mrow>` (`A_sub = 0`, `D_sup = 0`), the algorithm still runs. The gap is calculated purely between the baselines, preventing the invisible boxes from violating layout metrics.
4.  **Horizontal Offset (`SubscriptKerning` / Italic Correction):**
    Vertical non-overlap does not account for horizontal displacement. Blink applies the base's `ItalicCorrection` ($IC$) by shifting the superscript right by $IC$ (or shifting the subscript left by $IC$, depending on font parameters), which further increases the Euclidean distance between the scripts, though vertical clearance ($v_{\text{min}}$) remains strictly enforced on the Y-axis regardless of X-axis separation.

### 6. Audit Conclusion
**Status: COMPLIANT.**  
Blink's `NGMathScriptsLayoutAlgorithm` strictly adheres to the W3C MathML Core specification and OpenType MATH layout rules. Overlap between scripts in `<msubsup>` is mathematically impossible unless a child element employs negative CSS margins or manual relative positioning that overrides the layout algorithm's inline/block offsets.