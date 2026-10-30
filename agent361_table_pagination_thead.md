**AUDIT REPORT: Blink Table `<thead>` Pagination Space Reservation (Top Space)**
**Auditor:** Agent 361
**Target Subsystem:** Chromium Blink Layout Engine (LayoutNG Table Fragmentation)
**Subject:** Top Space Reservation for Repeated Table Headers (`<thead>`)

---

### 1. Executive Summary
In Blink’s LayoutNG architecture, paginating tables with repeating headers (`<thead>`) requires pre-calculating and reserving block-size at the top of every subsequent fragmentainer (page or column) after the first. This audit details the exact mechanisms, constraints, and edge-case mitigations Blink employs to reserve this top space during the fragmentation phase.

### 2. Core Components Involved
*   `NGTableLayoutAlgorithm`: Orchestrates the overall table layout, including measuring the `<thead>` and passing reservation metrics down the tree.
*   `NGTableAlgorithmUtils`: Contains helper logic to determine if a section is repeatable based on fragmentation constraints.
*   `NGConstraintSpace` / `NGConstraintSpaceBuilder`: Carries the `repeated_header_block_size` down to child layout algorithms (such as `NGTableSectionLayoutAlgorithm`).
*   `NGBoxFragmentBuilder`: Manages the placement of the repeated header fragment at the top of the current fragmentainer and adjusts the offsets of subsequent table sections (`<tbody>`).

---

### 3. The Top Space Reservation Lifecycle

#### Phase 1: Qualification and Measurement
Before space can be reserved, Blink must determine if the `<thead>` is eligible for repetition. 
1.  **CSS Check:** The `<thead>` must have `break-inside: avoid` (either explicitly or implicitly managed by the engine for headers).
2.  **Unconstrained Measurement:** `NGTableLayoutAlgorithm` performs an initial layout pass on the `<thead>` using an unconstrained block-size to determine its intrinsic height (`thead_block_size`).
3.  **The 25% Rule (Crucial Constraint):** To prevent infinite pagination loops (where a header consumes the entire page, leaving no room for content, forcing a page break, and repeating infinitely), Blink enforces a strict threshold. 
    *   *Condition:* The `thead_block_size` must not exceed **25%** of the fragmentainer's total block-size (`fragmentainer_space_at_start`).
    *   If `thead_block_size > (fragmentainer_block_size * 0.25)`, repetition is aborted, and no top space is reserved on subsequent pages.

#### Phase 2: Constraint Space Propagation
Once the `<thead>` is validated for repetition, its height must be communicated to the algorithms laying out the rest of the table (specifically, the `<tbody>` and `<tfoot>`).
1.  As `NGTableLayoutAlgorithm` prepares to lay out children in a new fragmentainer, it invokes `NGConstraintSpaceBuilder`.
2.  It sets the **`repeated_header_block_size`** property on the `NGConstraintSpace` passed to the table sections.
3.  This effectively shrinks the *available* fragmentainer block-size seen by the `<tbody>` rows, ensuring they break earlier to account for the space already consumed at the top by the repeated `<thead>`.

#### Phase 3: Top Space Reservation & Placement (Fragmentation)
When a table crosses a fragmentation boundary (moves to Page $N$, where $N > 1$):

1.  **Offset Adjustment:** At the very start of the new fragmentainer, the `NGTableLayoutAlgorithm` checks for the presence of a repeatable `<thead>` via the incoming `NGBreakToken`.
2.  **Cloning the Fragment:** Instead of running the full layout algorithm on the `<thead>` again, Blink clones the physical fragment generated during the first page's layout (using `NGRepeatable` logic). This ensures high performance and visual consistency.
3.  **Consuming Top Space:** 
    *   The cloned `<thead>` fragment is added to the `NGBoxFragmentBuilder` at block-offset `0` (or immediately following any repeatable `<caption>` or top border/padding if applicable, though CSS specs generally dictate captions do not repeat, and borders are handled via `box-decoration-break`).
    *   The builder’s internal `child_block_offset` cursor is incremented by `thead_block_size`.
4.  **Border-Collapse Resolution:** If the table uses `border-collapse: collapse`, the top space reservation must also account for the collapsed border width between the `<thead>` and the first row of the `<tbody>` on that page. Blink reserves space for the half-border protruding from the `<thead>` and merges it with the incoming `<tbody>` row.

---

### 4. Edge Cases Audited

*   **First Fragmentainer (Page 1):** Top space is *not* "reserved" via the repetition mechanism on the first page. The `<thead>` simply flows naturally as the first child of the table. Reservation logic only activates upon processing a `NGTableBreakToken` indicating resumption in a new fragmentainer.
*   **Orphaned Headers:** If a table starts near the bottom of Page 1, and only the `<thead>` fits, Blink will push the entire table (or the `<thead>`) to Page 2 to avoid an orphaned header at the bottom of Page 1. Thus, top space reservation on Page 2 becomes the *initial* placement, not a repeated placement.
*   **Nested Tables:** If a table with a `<thead>` is nested inside another table with a `<thead>`, the `NGConstraintSpace` accumulates the `repeated_header_block_size` additively. The inner `<thead>` is evaluated against the remaining fragmentainer space *after* the outer `<thead>` has reserved its top space.
*   **Struts and Forced Breaks:** If a `<tbody>` row has `break-before: page`, the forced break triggers a new fragmentainer. The top space reservation immediately intercepts the top of the new page, placing the `<thead>` *before* the row that requested the break.

### 5. Audit Conclusion
Blink's LayoutNG successfully isolates top space reservation for `<thead>` elements by leveraging immutable fragment cloning and passing reservations down via `NGConstraintSpace`. The hard-coded 25% fragmentainer height limit acts as a fail-safe against layout-inducing DoS (infinite pagination loops). 

**Status:** COMPLIANT / OPTIMAL. **Agent 361 signing off.**