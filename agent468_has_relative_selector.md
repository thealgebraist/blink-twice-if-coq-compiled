**AUDIT LOG: BLINK ENGINE // COMPONENT: CSS SELECTOR MATCHING**
**AUDITOR: AGENT 468**
**SUBJECT: `:has()` Pseudo-Class Relative Anchor Traversal Architecture**

### 1. Executive Summary
The `:has()` relational pseudo-class introduces a lookahead mechanism in Blink’s traditionally right-to-left (bottom-up) `SelectorChecker`. Evaluating `:has(<relative-selector-list>)` requires establishing the subject element as the **Relative Anchor Element** and performing a localized, directional DOM traversal. Unconstrained, this introduces $O(N^2)$ or $O(N^3)$ complexity. This audit details the exact traversal mechanics, scope bounding, and cache-flag mutations utilized by Blink (`third_party/blink/renderer/core/css/`) to execute relative anchor traversal within performance budgets.

---

### 2. Establish the Anchor: `SelectorCheckingContext`
When `SelectorChecker::MatchSelector` encounters a `CSSSelector::kPseudoHas`, normal right-to-left compound evaluation halts. 
1. The current `Element*` being evaluated is locked in as the `relative_anchor_element`.
2. A sub-context (`SelectorCheckingContext`) is instantiated for the inner relative selector.
3. Blink injects an synthetic internal pseudo-class—`kPseudoRelativeAnchor`—at the leftmost position of the inner selector chain. 
   * *Example:* `div:has(> .child)` is parsed internally for the sub-context as `:relative-anchor > .child`.
   * *Evaluation Flow:* Although the relative selector represents a downward/forward lookahead from the anchor, Blink **preserves right-to-left evaluation** for the inner selector. It finds candidate `.child` elements first, then traverses *upward/backward* to verify if the chain terminates at the `kPseudoRelativeAnchor` (the `div`).

---

### 3. The Traversal Mechanism: `CheckPseudoHas`
To find candidate terminal elements (the rightmost compound of the relative selector) without scanning the entire Document, Blink utilizes `CheckPseudoHasArgumentTraversalIterator`.

#### A. Determining Traversal Scope (`CheckPseudoHasArgumentContext`)
Before touching the DOM, Blink analyzes the combinators adjacent to the implicit `:relative-anchor` to define the **Traversal Scope**:
*   **Descendant (` `) or Child (`>`):** The search space is strictly bounded to the subtree of the `relative_anchor_element`.
*   **Next-Sibling (`+`) or Subsequent-Sibling (`~`):** The search space is extended to the siblings following the `relative_anchor_element`.
*   **Compound (`~` followed by ` `):** The search space covers the subtrees of all subsequent siblings of the `relative_anchor_element`.

#### B. Fixed Depth and Adjacent Distance Optimization
Blink extracts two crucial constraints from the relative selector before iterating:
1.  **`depth_limit`:** If the selector uses only `>` combinators (e.g., `:has(> a > b)`), the maximum tree depth is fixed (Depth = 2). The iterator will not descend past grandchildren.
2.  **`adjacent_distance_limit`:** If the selector uses `+` combinators, sibling traversal is capped at the exact count of `+` combinators.

#### C. Execution of the Iterator
The `CheckPseudoHasArgumentTraversalIterator` walks the DOM *in reverse* or *forward* depending on optimization flags, yielding candidate elements (`Element*`) within the bounded scope:
1. The iterator yields a candidate element inside the scope.
2. `SelectorChecker` attempts to match the rightmost compound of the `:has()` argument against this candidate.
3. If it matches, `SelectorChecker` walks the selector chain right-to-left (moving up the DOM tree via parents or left via previous siblings).
4. **Termination:** The match succeeds *if and only if* the final `kPseudoRelativeAnchor` matches the original `relative_anchor_element`.

---

### 4. Bailout & Caching Optimizations
Raw traversal per anchor is catastrophic for deeply nested DOMs (e.g., `:has(.target)` on `<html>`, `<body>`, `<div>`). Agent 468 notes three critical mitigations implemented in Blink:

#### A. `CheckPseudoHasFastRejectFilter` (Bloom Filter)
Before initiating traversal for an anchor, Blink allocates a fast-reject Bloom filter (using `IdentifierFilter`). 
* As the iterator traverses the anchor's subtree/siblings for the first time, it hashes the TagNames, IDs, and ClassNames of all encountered elements into the filter.
* For subsequent `:has()` checks on the same anchor, if the required terminal identifiers (e.g., `.target`) are absent from the Bloom filter, Blink aborts the DOM traversal in $O(1)$ time.

#### B. `CheckPseudoHasCacheScope` (Result Caching)
Because `:has()` matching walks the tree, checking `div:has(.a)` on an ancestor often repeats work needed for a descendant `div:has(.a)`.
* Blink maintains a temporary per-style-recalc map (`CheckPseudoHasResultCache`).
* When evaluating a non-depth-limited descendant selector (like `:has(.a)`), if a candidate `.a` is found, Blink walks **up** the ancestor chain from `.a` to the `relative_anchor_element` and marks *every intermediate element* in the cache as `kChecked | kMatched`.
* If an anchor is evaluated and its subtree yields no matches, the anchor (and potentially its un-matched descendants) are cached as `kChecked` (false) to prevent redundant subtree walks.

#### C. Tree-Structural Early Returns
For sibling-combinator anchors (`:has(+ .a ~ .b)`), if the iterator hits the end of the sibling list and fails, it records the failure in the cache for previous siblings, preventing an $O(S^2)$ sibling walk where $S$ is the number of children in a flat container.

---

### 5. Style Invalidation Flags (Mutation Auditing)
A passive traversal is insufficient; Blink must know when a DOM mutation invalidates a `:has()` anchor. During the traversal phase, `SelectorChecker` mutates bitfields on `ElementRareData` (or `Node` flags) of the traversed nodes:

1.  **`SetAncestorsOrAncestorSiblingsAffectedByHas()`:** Applied to elements traversed during the walk. If a DOM mutation occurs inside a node with this flag, Blink knows it must walk *up* and *left* to find an anchor to invalidate.
2.  **`AffectedBySubjectHas`:** Set on the `relative_anchor_element` itself. Indicates this element’s computed style directly depends on a `:has()` evaluation.
3.  **`AffectedByPseudoInHas`:** Set if the relative selector contains state-dependent pseudo-classes (e.g., `:has(:hover)`, `:has(:focus)`), triggering targeted invalidation paths during user interaction events.

### 6. Audit Conclusion
Blink’s relative anchor traversal avoids naive top-down matching by bounding the search space via combinator analysis (`CheckPseudoHasArgumentContext`), utilizing reverse-DOM iterators to populate upward caches (`CheckPseudoHasCacheScope`), and short-circuiting impossible matches via Bloom filters (`CheckPseudoHasFastRejectFilter`). 

**STATUS:** Architecture verified. Traversal bounds are intact. End of report.