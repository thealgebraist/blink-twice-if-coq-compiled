**AUDIT LOG: AGENT 356**
**TARGET:** Chromium / Blink Rendering Engine (LayoutNG)
**SUBJECT:** `break-inside: avoid` Penalty Assignment and Minimization Mechanics

---

### 1. ARCHITECTURAL OVERVIEW
In Blink’s LayoutNG fragmentation engine (`ng_fragmentation_utils`), CSS fragmentation rules (`break-inside`, `break-before`, `break-after`) are not treated as absolute boolean constraints unless forced (`break-before: page`). Instead, they are mapped to a tiered hierarchy of **Break Appeal** (`NGBreakAppeal`). 

Rather than calculating additive numerical penalties like TeX’s line-breaking algorithm, Blink utilizes a **discrete state-degradation model**. A "penalty" is assigned by capping the maximum possible appeal of a candidate break opportunity. Minimization of this penalty is achieved by greedily searching for the highest appeal score that prevents fragmentainer overflow.

---

### 2. PENALTY ASSIGNMENT (THE APPEAL HIERARCHY)

Every potential break opportunity (class A, B, or C per CSS Fragmentation Module Level 3) is evaluated and assigned an `NGBreakAppeal` value. These values are ordered from highest (most desirable break) to lowest (most heavily penalized break):

1. **`kBreakAppealPerfect` (Penalty: 0)**
   * No fragmentation rules are violated. Content fits cleanly, and no `avoid` rules apply to the current boundary or ancestor containers.
2. **`kBreakAppealViolatingBreakAvoid` (Penalty: Moderate)**
   * **Primary Target of Audit:** Assigned when a break opportunity falls inside an element (or across a boundary) governed by `break-inside: avoid`, `break-inside: avoid-page`, `break-inside: avoid-column`, or `break-before/after: avoid`.
3. **`kBreakAppealViolatingOrphansAndWidows` (Penalty: High)**
   * Assigned when breaking at a line box violates the `orphans` or `widows` constraints of a block container. (Note: Blink prioritizes keeping `avoid` blocks together *less* than respecting orphans/widows in certain contexts, or combines their evaluation depending on the layout pass).
4. **`kBreakAppealLastResort` (Penalty: Severe)**
   * Assigned to monolithic content splits, breaking inside unbreakable elements, or violating strict layout constraints because no other valid break points exist before the fragmentainer overflows.

#### Assignment Mechanism during Layout
As the `NGBlockLayoutAlgorithm` traverses the box tree via the `NGConstraintSpace`:
* **Propagation:** When entering a child node with `break-inside: avoid`, the parent algorithm updates the child's `NGConstraintSpace` or tracks the constraint internally in the `NGFragmentBuilder`.
* **Evaluation:** At every valid breakpoint (e.g., between block siblings or line boxes), `CalculateBreakAppeal()` is invoked.
* **Degradation:** The breakpoint starts at `kBreakAppealPerfect`. If the engine detects an active `break-inside: avoid` scope on the current element or any ancestor within the current fragmentation context, the appeal is clamped down via `std::min(current_appeal, kBreakAppealViolatingBreakAvoid)`.

---

### 3. PENALTY MINIMIZATION (APPEAL MAXIMIZATION)

Blink minimizes fragmentation penalties using a **Greedy Early-Break Strategy** paired with **State Rollback**. The engine tracks the "best" break opportunity seen so far within the current fragmentainer using an `NGBreakToken` and appeal tracker.

#### Step-by-Step Minimization Flow:

1. **Continuous Tracking (The "Early Break" Candidate):**
   As children are laid out sequentially within a fragmentainer (e.g., a multi-column flow or paginated view), the algorithm evaluates the appeal of breaking *before* each child. 
   * If the appeal is `kBreakAppealPerfect`, it is recorded as the `early_break_` candidate.
   * As more children are added, `early_break_` is continually overwritten by *later* breakpoints, provided their appeal is greater than or equal to the previously recorded `early_break_` appeal.

2. **Entering the Penalty Zone (`break-inside: avoid`):**
   When layout enters a block with `break-inside: avoid`, all internal breakpoints are penalized (clamped to `kBreakAppealViolatingBreakAvoid`). 
   * As the engine lays out the internal children of this block, it sees that their break appeals are *lower* than the `kBreakAppealPerfect` recorded just before the block started.
   * Consequently, the internal breakpoints do **not** overwrite the `early_break_` candidate unless no prior `kBreakAppealPerfect` existed in the fragmentainer.

3. **Overflow Detection & Triggering Minimization:**
   Minimization executes the moment a child exceeds the remaining fragmentainer space (`BfcBlockOffset` > fragmentainer block-size).
   * **Scenario A (Clean Evasion):** The `break-inside: avoid` block overflows the fragmentainer. The engine checks the breakpoint right at the overflow boundary. Its appeal is `kBreakAppealViolatingBreakAvoid`. The engine compares this to the stored `early_break_` (which has `kBreakAppealPerfect` right before the block). To minimize the penalty, the engine **aborts the current layout pass**, rolls back to the `early_break_`, and pushes the *entire* `break-inside: avoid` block to the next fragmentainer.
   * **Scenario B (Forced Violation / Penalty Acceptance):** The `break-inside: avoid` block is situtated at the very top of the fragmentainer (no prior `kBreakAppealPerfect` exists) and is taller than the fragmentainer itself. The `early_break_` tracker only contains `kBreakAppealViolatingBreakAvoid` candidates. Because pushing the block to the next page would result in an infinite loop or an unnecessarily empty fragmentainer, the engine accepts the penalty. It breaks at the latest possible internal breakpoint that holds the `kBreakAppealViolatingBreakAvoid` score, splitting the block across fragmentainers.

---

### 4. EDGE CASES & AUDIT VULNERABILITIES

* **Nested `avoid` Scopes:** Because `NGBreakAppeal` is a flat enum rather than an integer weight, Blink **flattens nested penalties**. Breaking inside *two* nested `break-inside: avoid` blocks carries the exact same `kBreakAppealViolatingBreakAvoid` score as breaking inside *one*. If a break must be forced, Blink will simply break as late as possible in the fragmentainer, rather than breaking at a boundary that violates only the outer `avoid` while sparing the inner `avoid`.
* **Monolithic Content Interaction:** Replaced elements (images), elements with `overflow: scroll/auto`, or elements with `contain: size/layout` are treated as monolithic (`kBreakAppealLastResort` internally). If placed inside a `break-inside: avoid` container, the monolithic constraint overrides the `avoid` penalty, forcing splits strictly at the boundaries of the monolithic element.
* **Margin Collapsing at Breakpoints:** When rolling back to an `early_break_` to minimize a `break-inside: avoid` penalty, previously collapsed margins must be un-collapsed and re-evaluated, occasionally causing layout thrashing (multiple passes of `NGBlockLayoutAlgorithm::LayoutWithEarlyBreak`).

**END OF REPORT - AGENT 356**