**AUDIT REPORT: Blink Layout Engine – Orphan Line Count Enforcement**
**Auditor:** Agent 359
**Target Component:** Chromium / Blink CSS Fragmentation (`LayoutNG` / `Core/Style`)
**Subject:** Minimum Line Count Constraint for `orphans` Property

---

### 1. Executive Summary
An audit of the Blink layout engine’s pagination and block fragmentation system confirms that the `orphans` CSS property is strictly constrained at both the parser level and the fragmentation layout level. The absolute minimum line count constraint for `orphans` is **1**. Values less than or equal to zero are invalid and rejected prior to layout computation.

### 2. Specification & Parser Constraints
Per the CSS Fragmentation Module Level 3 specification, the `orphans` property specifies the minimum number of lines of a block container that must be left in a fragment *before* a fragmentation break (page, column, or region).

*   **Data Type:** `<integer>`
*   **Minimum Allowed Value:** `1`
*   **Default (Initial) Value:** `2`
*   **Parser Enforcement:** In Blink's CSS parser (`css_properties.json5` and associated parsing logic), the property is restricted to positive, non-zero integers. Any CSS declaration attempting to set `orphans: 0` or a negative integer is dropped as a parse error, reverting the computed style to the inherited value or the initial value of `2`.

### 3. Computed Style Storage (`ComputedStyle`)
Once parsed, the value is stored in Blink's `ComputedStyle` object.
*   **Type Constraint:** Stored as an integer (`int16_t` or `unsigned` depending on the specific bitfield packing in `ComputedStyleBase`).
*   **Clamping:** To prevent overflow during layout calculations, the parser and style builder clamp excessively large integers, though the lower bound remains strictly clamped at `1`.

### 4. Layout Engine Enforcement (Blink `LayoutNG`)
During the block fragmentation phase (handled primarily by `NGBlockLayoutAlgorithm` and `NGFragmentBuilder`), Blink enforces the minimum line count constraint via the following execution flow:

#### A. Constraint Propagation
When a block formatting context is fragmented, the `orphans` value is retrieved via `Style().Orphans()`. Because the parser guarantees a minimum of `1`, the layout algorithm operates under the invariant that `orphans >= 1`.

#### B. Line Counting and Break Appeal
As inline content is laid out into line boxes (`NGLineBoxFragment`), the `NGBlockLayoutAlgorithm` tracks the number of lines generated in the current fragmentainer (column/page).
1.  **The "1-Line" Baseline:** If `orphans` is set to the minimum constraint of `1`, Blink permits a break immediately after the first line box, provided that the first line itself fits within the current fragmentainer. 
2.  **Violation Handling (`NGBreakAppeal`):** If a fragmentation break is needed before the `orphans` count is met (e.g., `orphans: 3`, and only 2 lines fit), Blink calculates a penalty. It assigns a lower `NGBreakAppeal` (`kBreakAppealLastResort`) to that break point.
3.  **Relocation:** The engine will attempt to backtrack and push the entire block (or the necessary subset of lines) to the next fragmentainer so the minimum orphan count is respected.

### 5. Edge Cases & Override Conditions (Constraint Relaxation)
Audit reveals that the `orphans` minimum line count constraint is **soft** during layout and will be violated by the engine under specific geometric emergencies to prevent infinite loops or data loss:

*   **Total Line Deficit:** If a block contains fewer total lines than the specified `orphans` value (e.g., a 1-line paragraph with `orphans: 2`), the constraint is dynamically capped at the actual number of lines available.
*   **Unbreakable Monolithic Content:** If the first line itself is taller than the fragmentainer, Blink forces the line to stay to guarantee forward progress, effectively ignoring pagination aesthetics.
*   **`widows` Conflict:** If a block has insufficient lines to satisfy both `orphans` and `widows` simultaneously, the engine prioritizes avoiding an empty fragmentainer, which may result in one of the constraints failing.
*   **Forced Breaks:** Explicit breaks (e.g., `break-before: page` or `<br>` with break properties) override the `orphans` constraint entirely.

### 6. Audit Conclusion
Blink's enforcement of the `orphans` minimum line count constraint is **Compliant**. The system successfully prevents zero or negative line minimums at the ingestion layer (`>= 1` invariant) and utilizes heuristic appeal-based backtracking in `LayoutNG` to honor the requested line count wherever geometrically feasible. 

**End of Report.**
*Agent 359 signing off.*