**AUDIT REPORT: BLINK LAYOUT ENGINE**
**Auditor:** Agent 360
**Subject:** CSS `widows` Property – Minimum Line Count Enforcement
**Target Component:** Blink Block Layout / LayoutNG (`third_party/blink/renderer/core/layout/ng/`)

---

### 1. Executive Summary
Within the Blink rendering engine, the **minimum line count constraint** for the CSS `widows` property is strictly enforced during the block fragmentation phase. A "widow" refers to the last line(s) of a block container that fall at the top of a new page, column, or region following a fragmentation break. 

The minimum constraint dictates both the **validity of the CSS value** during parsing and the **line-breaking behavior** during LayoutNG calculation.

---

### 2. Constraint Specifications

#### A. CSS Parsing Constraint (Absolute Minimum)
*   **Minimum Allowed Value:** `1` (Integer)
*   **Specification:** CSS Fragmentation Module Level 3
*   **Blink Enforcement:** During the style resolution phase (`css_properties.json5` and `StyleBuilder`), Blink enforces that the `widows` property accepts only positive non-zero integers (`<integer [1,∞]>`). 
*   **Violation Handling:** Any specified value of `0`, negative integers, or non-integer values are flagged as parse errors and ignored, reverting the property to its inherited value or the initial default.

#### B. Initial (Default) Constraint
*   **Default Value:** `2`
*   **Blink Enforcement:** If unstated by the author, Blink initializes the `ComputedStyle` for `widows` to `2`. This means by default, Blink will attempt to ensure at least 2 lines of a fragmented paragraph appear at the top of the subsequent fragmentainer.

---

### 3. LayoutNG Algorithmic Enforcement
In Blink's modern LayoutNG architecture, the `NGBlockLayoutAlgorithm` and `NGFragmentBuilder` handle the minimum line count constraint via the following operational logic:

#### Condition 1: Total Line Count < `widows` Constraint
If a block container has fewer total lines than the specified `widows` minimum (e.g., a 2-line paragraph with `widows: 3`):
*   **Enforcement:** The `widows` constraint cannot be strictly met if a break occurs. Blink elevates the break avoidance between the lines, effectively treating the block as monolithic regarding internal breaks, pushing the entire block to the next fragmentainer.

#### Condition 2: Conflict with `orphans` Constraint
If the sum of `orphans` (minimum lines before the break) and `widows` (minimum lines after the break) exceeds the total number of lines in the block (`Total Lines < orphans + widows`):
*   **Enforcement:** Blink cannot satisfy both minimums via an internal break. The engine will refuse to break inside the block, moving the entire element to the next column/page to prevent violating either minimum constraint.

#### Condition 3: Standard Enforcement (Backtracking)
When a fragmentation break is triggered because a line exceeds the remaining space in the current fragmentainer:
1.  Blink calculates how many lines remain to be laid out in the next fragmentainer.
2.  If `Remaining Lines < ComputedStyle::Widows()`, a **constraint violation** is detected.
3.  **Resolution:** The engine backtracks into the *current* fragmentainer and forces an earlier break. It pulls lines from the bottom of the current fragmentainer and pushes them to the next until the `widows` minimum count is met (provided this does not violate the `orphans` minimum in the current fragmentainer).

#### Condition 4: Precedence Overruled by `break-inside: avoid`
If `break-inside: avoid` is applied, the minimum line count constraint for `widows` is bypassed entirely, as the effective minimum line count required to stay together becomes 100% of the block's lines.

---

### 4. Audit Conclusion
Blink's enforcement of the `widows` minimum line count constraint is **COMPLIANT** with W3C CSS Fragmentation specifications. The hard floor is locked at `1` at the parser level, defaults to `2` at the computed style level, and dynamically yields to `orphans` and container total line counts during the LayoutNG fragmentation pass to prevent infinite layout loops. 

*End of Report – Agent 360*