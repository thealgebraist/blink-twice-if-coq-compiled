**AUDIT LOG: AGENT 358**
**SUBJECT:** Chromium Blink LayoutNG Engine — Fragmentation Subsystem
**AUDIT TARGET:** Forced Break After Page (`break-after: page`) & Transition State Mechanics
**STATUS:** ACTIVE

---

### 1. EXECUTIVE SUMMARY
In the Blink rendering engine (specifically within the LayoutNG fragmentation architecture), a forced break is not handled immediately at the termination of the layout node that declares it. Instead, it undergoes a state-transition process. The **`break-after: page`** property is extracted from the originating box, propagated upward through the layout tree, and transformed into a pending **`break-before: page`** requirement for the subsequent in-flow sibling.

Below is the detailed mechanical breakdown of the forced break transition during the LayoutNG fragmentation phase.

---

### 2. THE FORCED BREAK TRANSITION LIFECYCLE

#### Phase I: Style Resolution & Normalization
Before layout begins, Blink’s Style Engine resolves CSS fragmentation properties onto the `ComputedStyle` object of the target `LayoutObject`.
*   **Legacy Mapping:** Legacy properties (e.g., `page-break-after: always`) are aliased at parse time to the modern CSS Fragmentation Module Level 3 specification (`break-after: page`).
*   **Value Assignment:** The `EBreakBetween` enum on the node's `ComputedStyle` is set to `EBreakBetween::kPage`.

#### Phase II: Fragment Generation & Upward Propagation
During the `NGBlockLayoutAlgorithm` execution for a given fragmentation context (such as a paged media Printing context or a CSS Multi-column container):

1.  **Child Layout Execution:** The parent container invokes the layout algorithm on the target child (`Node A`), passing down an `NGConstraintSpace` that includes the current `fragmentainer_space_available`.
2.  **Builder Population:** `Node A` completes its internal layout. Before returning its `NGLayoutResult`, the `NGBoxFragmentBuilder` evaluates `Node A`’s `ComputedStyle` for break properties.
3.  **Break Consolidation:** If `Node A` contains descendant blocks, any `break-after` value from its *last* in-flow child is propagated up and compared against `Node A`’s own `break-after` property. Blink resolves this via **`JoinFragmentainerBreakValues()`**, where forced breaks (`kPage`, `kColumn`, `kLeft`, `kRight`, `kRecto`, `kVerso`) strictly override unforced/avoidance values (`kAuto`, `kAvoid`).
4.  **Result Attachment:** The winning `EBreakBetween::kPage` value is stored on the `NGLayoutResult` (specifically via `SetFinalBreakAfter()`).

#### Phase III: The In-Flow Transition (The Hand-off)
The parent `NGBlockLayoutAlgorithm` receives the `NGLayoutResult` of `Node A`. At this juncture, the break does not immediately sever the fragmentainer. It enters a **Pending State**.

1.  **State Storage:** The parent algorithm records the `final_break_after` value from `Node A` into its internal state tracker (`NGPreviousInflowPosition`).
2.  **Sibling Resolution:** The parent algorithm advances its `NGLayoutInputNode` iterator to the next in-flow child (`Node B`).
3.  **Break Merging:** Before laying out `Node B`, the engine invokes **`CalculateBreakBetweenValue()`**. This combines:
    *   The propagated `break-after` state from `Node A` (`kPage`).
    *   The intrinsic `break-before` state of `Node B` (and its first in-flow descendants).
4.  **Transition Trigger:** Because `kPage` is a forced break, the merged result evaluates to `EBreakBetween::kPage`. The engine now executes **`BreakBeforeChildIfNeeded()`**.

*Audit Note: If `Node A` is the final child in the formatting context, the `break-after: page` value continues to propagate up the ancestor chain until it finds a subsequent in-flow sibling at a higher level. If it reaches the root of the fragmentation context (the document root in paged media) with no subsequent content, **the forced break is suppressed** to prevent generating a trailing blank page.*

#### Phase IV: Fragmentainer Termination & Tokenization
Once `BreakBeforeChildIfNeeded()` detects the forced `kPage` requirement before `Node B`, the layout transition is finalized:

1.  **Space Exhaustion:** The current fragmentainer (Page $N$) is marked as out of space.
2.  **Margin Truncation:** Any block-end margins following `Node A` that collapsed through to the break boundary are truncated/clamped to zero, as margins cannot cross a forced break boundary into the next fragmentainer without explicit `box-decoration-break` rules.
3.  **Break Token Creation:** The `NGBoxFragmentBuilder` for the parent container creates an **`NGBlockBreakToken`** targeting `Node B`.
    *   `is_break_before` is flagged as `true`.
    *   `is_forced_break` is flagged as `true`.
4.  **Algorithm Exit:** The parent layout algorithm halts further child processing for Page $N$ and returns the partial `NGPhysicalBoxFragment` (containing `Node A` and preceding siblings) along with the newly minted `NGBlockBreakToken` to the pagination root (`NGPageLayoutAlgorithm`).

#### Phase V: Resumption in Next Fragmentainer
1.  **New Fragmentainer Instantiation:** The pagination root generates a new page container (Page $N+1$) with a fresh `NGConstraintSpace` where `fragmentainer_offset` is reset to `0`.
2.  **Token Consumption:** The parent container’s layout algorithm is re-invoked for Page $N+1$, receiving the `NGBlockBreakToken` from Page $N$ as an input parameter.
3.  **Fast-Forwarding:** The algorithm skips `Node A` (already fully laid out) and immediately begins layout at `Node B` at the top of Page $N+1$.
4.  **Margin Preservation:** Because the `NGBlockBreakToken` is marked with `is_forced_break = true`, the `block-start` margin of `Node B` is **preserved** at the top of Page $N+1$ (unlike unforced/soft breaks, where block-start margins at the top of a new page are collapsed to zero).

---

### 3. AUDIT SUMMARY OF EDGE-CASE VECTORS
*   **Column-Inside-Page Contexts:** If `break-after: page` occurs inside a `multicol` container that is itself inside a paged media context, the `kPage` break bypasses the immediate column fragmentainer, forces breaks through all remaining columns on the current page, and propagates out to the `NGPageLayoutAlgorithm` level.
*   **Out-of-Flow (OOF) Descendants:** Absolute or fixed-positioned elements do not participate in the `EBreakBetween` propagation chain; they neither trigger nor consume the pending `break-after` state.

**END OF AUDIT REPORT — AGENT 358**