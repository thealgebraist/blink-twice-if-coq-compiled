**Audit Report: Blink MathML Superscript Shift (`v`)**  
**Auditor:** Agent 373  
**Target Subsystem:** `third_party/blink/renderer/core/layout/mathml/` (specifically `MathScriptsLayoutAlgorithm`)  
**Reference Specification:** MathML Core Specification (Section: *Scripts and Limits - `<msup>`, `<msubsup>`*)

---

### 1. Executive Summary
An audit of the Blink layout engine's MathML implementation reveals strict adherence to the MathML Core specification regarding the vertical shift of superscripts (denoted as $v$ in layout algorithms). Blink enforces **non-negativity** via explicit clamping (`std::max`) against zero, and establishes **lower bounds** using a cascading maximization of OpenType MATH table metrics and geometric clearances relative to the base and subscript boxes.

---

### 2. Shift Up ($v$) Non-Negativity

In MathML Core, the superscript shift parameter $v$ represents the upward displacement of the superscript baseline relative to the base's baseline. 

*   **Audit Finding:** The superscript shift $v$ is strictly non-negative ($v \ge 0$). A superscript is never shifted below the baseline of the base expression by the automatic layout algorithm, even if the user specifies a large negative `voffset` (which is ignored in MathML Core) or if the font metrics contain malformed negative values.
*   **Blink Implementation:** During the initialization of the shift calculation in `MathScriptsLayoutAlgorithm`, the shift $v$ is initialized or clamped using `LayoutUnit()`.
    ```cpp
    LayoutUnit shift_up = std::max(LayoutUnit(), ...);
    ```

---

### 3. Lower Bounds of the Superscript Shift

To determine the exact value of $v$, Blink calculates a series of lower bounds based on the **OpenType MATH table** (or fallback heuristics if the font lacks a MATH table) and the geometry of the child layout boxes.

#### A. Standalone Superscript (`<msup>`)
For a standard superscript without a subscript, $v$ is bounded by three primary metrics:

1.  **Zero Bound (Non-Negativity):**
    $$v \ge 0$$
2.  **Font Metric Bound ($u_1$ or $u_2$):**
    Depending on the `math-shift` CSS property (normal vs. compact/cramped):
    *   If `math-shift: normal`: $v \ge \text{SuperscriptShiftUp}$
    *   If `math-shift: compact`: $v \ge \text{SuperscriptShiftUpCramped}$
3.  **Base Ascent Drop Bound:**
    Prevents the superscript from sitting too high on tall bases, anchoring it relative to the top of the base box:
    $$v \ge \text{BaseAscent} - \text{SuperscriptBaselineDropMax}$$
4.  **Minimum Bottom Clearance Bound:**
    Ensures the bottom (descent) of the superscript stays above a minimum threshold determined by the font's x-height:
    $$v - \text{SuperscriptDescent} \ge \text{SuperscriptBottomMin}$$
    $$\implies v \ge \text{SuperscriptBottomMin} + \text{SuperscriptDescent}$$

**Resolved `<msup>` Bound in Blink:**
$$v = \max\Big(0,\; u,\; \text{BaseAscent} - \text{DropMax},\; \text{BottomMin} + \text{SupDescent}\Big)$$

---

#### B. Combined Subscript-Superscript (`<msubsup>`)
When a subscript (shifted down by $w$) is simultaneously present, two additional geometric bounds are enforced on $v$ to prevent collisions and maintain visual hierarchy.

5.  **Maximum Bottom with Subscript Bound:**
    In a combined script, the bottom of the superscript has a stricter minimum height requirement than in `<msup>`:
    $$v - \text{SuperscriptDescent} \ge \text{SuperscriptBottomMaxWithSubscript}$$
    *(If this bound is violated, $v$ is increased by the deficit $\Delta$, and the subscript shift $w$ is decreased by the same $\Delta$, effectively shifting both scripts upward).*
6.  **Sub-Sup Gap Collision Bound:**
    The vertical gap between the bottom of the superscript box and the top of the subscript box must be at least $\text{SubSuperscriptGapMin}$:
    $$(v - \text{SuperscriptDescent}) - (\text{SubscriptAscent} - w) \ge \text{SubSuperscriptGapMin}$$
    *   **Blink Resolution:** If the current shifts $v$ and $w$ result in a gap smaller than $\text{SubSuperscriptGapMin}$, Blink resolves the collision by first attempting to push the superscript *up* (up to the `SuperscriptBottomMaxWithSubscript` threshold), and then pushing the subscript *down* ($w$) to satisfy the remaining gap requirement.

---

### 4. Edge Cases & Fallback Verification

*   **Missing OpenType MATH Table:** If the active `SimpleFontData` does not contain a valid `MATH` table, Blink falls back to `MathMLStyle` heuristics (multipliers of the font's `x-height` and `em` size). Because `x-height` is inherently non-negative, the fallback bounds preserve non-negativity.
*   **Negative Descent/Ascent:** If an author uses negative margins or CSS transforms inside the `<msup>` child, `SupDescent` or `BaseAscent` can become negative. Blink’s explicit `LayoutUnit()` (0) floor in the `std::max` chain ensures that negative child metrics cannot pull $v$ below zero.
*   **LayoutUnit Saturation:** For astronomically large `font-size` values, `LayoutUnit` arithmetic clamps at `LayoutUnit::Max()`, preventing integer overflow wrap-around into negative territory.

**Status:** **COMPLIANT**. Blink's `MathScriptsLayoutAlgorithm` accurately enforces both non-negativity and the multi-tiered OpenType lower bounds for superscript shifts. 

*End of Audit — Agent 373*