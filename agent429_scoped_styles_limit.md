**AUDIT LOG // AGENT 429**
**SUBJECT:** Blink Engine `@scope` Lower Boundary Exclusion (Donut-Hole Culling)
**COMPONENT:** `third_party/blink/renderer/core/css/`

### 1. Executive Summary: The Donut-Hole Paradigm
In CSS Cascading and Inheritance Level 6, the `@scope (<scope-start>) to (<scope-end>)` rule creates a **donut scope**—a bounded DOM subtree with one or more interior subtrees excised. "Donut-hole boundary culling" is the mechanism within Blink’s `SelectorChecker` and `ElementRuleCollector` that halts style resolution and selector matching when a DOM traversal crosses the inclusive upper boundary (`<scope-start>`) into the exclusive lower boundary (`<scope-end>`).

### 2. Core Culling Architecture (`StyleScopeFrame`)
To prevent catastrophic $O(N \times M)$ upwards DOM traversals for every candidate element, Blink utilizes a stack-allocated caching mechanism: `StyleScopeFrame`.

*   **Frame Instantiation:** During the top-down style recalculation pass (`Element::RecalcStyle`), a `StyleScopeFrame` is instantiated on the stack, linked to its parent frame (`StyleScopeFrame* parent_`).
*   **Activation Caching:** The frame caches `StyleScopeActivation` instances for the current element, storing the active `@scope` roots (`<scope-start>`) and the calculated limit elements (`<scope-end>`).
*   **Amortized Culling:** When evaluating a child element, Blink queries the parent `StyleScopeFrame` to instantly determine if the current node has already fallen into a donut hole, bypassing redundant selector evaluations.

### 3. The Boundary Culling Algorithm
When `ElementRuleCollector` processes a `RuleData` entry wrapped in a `StyleScope`, it delegates validation to `SelectorChecker::CheckScope`. The culling executes in three distinct phases:

#### Phase A: Target Exclusivity Check (Boundary Condition)
By specification, the `<scope-end>` boundary is **exclusive** (unlike `<scope-start>`, which is inclusive).
1.  If the candidate element (`element`) matches the `<scope-end>` selector (evaluated in the context of the `<scope-start>` root), it is the physical rim of the donut hole.
2.  **Action:** The element is immediately culled. The rule does not apply to the boundary node itself.

#### Phase B: Upward Traversal & Donut-Hole Interception
For a rule to match a target `element`, there must exist a valid `<scope-start>` ancestor reachable *without* passing through a `<scope-end>` node.
1.  Blink initiates a bottom-up traversal from `element` toward the document root (or leverages the `StyleScopeFrame` parent chain).
2.  At each ancestor node $A_i$:
    *   **Limit Check:** Does $A_i$ match `<scope-end>` (scoped to a valid root above it)? If **TRUE**, the traversal has hit a donut hole. The path is tainted. **CULL.**
    *   **Root Check:** Does $A_i$ match `<scope-start>`? If **TRUE** (and no limit was encountered on the path from `element` to $A_i$), a valid scope activation is confirmed. **PASS.**

#### Phase C: Nested Scope Disambiguation (Donut-in-Donut)
A critical edge case audited by Agent 429 is overlapping scopes:
```html
<div class="light"> <!-- Root 1 -->
  <div class="dark"> <!-- Limit 1 (Donut Hole) -->
    <div class="light"> <!-- Root 2 -->
      <p>Target</p>
    </div>
  </div>
</div>
```
If the rule is `@scope (.light) to (.dark) { p { color: red; } }`:
*   When evaluating `<p>`, the upward traversal hits `Root 2` (`.light`) *before* it hits `Limit 1` (`.dark`).
*   **Blink Culling Logic:** Because `<scope-end>` is strictly evaluated *relative* to a specific `<scope-start>` activation, `Limit 1` only terminates the scope of `Root 1`. `Root 2` establishes a fresh activation context inside the hole of `Root 1`. The culling algorithm halts at `Root 2` and marks `<p>` as **VALID**.

### 4. Selector Evaluation Context (`:scope` vs. `&`)
During limit evaluation (`CheckScopeLimit`), Blink must alter the `SelectorCheckingContext`:
*   When evaluating `<scope-end>`, the `:scope` pseudo-class inside the limit selector (e.g., `@scope (.card) to (:scope > .content)`) must resolve to the candidate `<scope-start>` root, **not** the candidate element being styled, and **not** the `<scope-end>` element itself.
*   Blink injects the candidate `StyleScopeActivation.root` into `SelectorCheckingContext.scope` before invoking `SelectorChecker::Match` on the limit selector list.

### 5. Shadow DOM & Flat Tree Culling
Audit confirms that `@scope` culling respects encapsulation boundaries:
*   Traversals between `element`, `<scope-end>`, and `<scope-start>` are strictly confined to the same TreeScope unless explicitly bridged by pseudo-elements/slotted content rules.
*   `ParentElementOrShadowRoot()` is bypassed in favor of `LayoutTreeBuilderTraversal` or strict DOM tree traversal depending on whether `<scope-start>` was triggered via `:host` or standard tree-abiding selectors. A `<scope-end>` inside a Shadow Tree cannot cull a `<scope-start>` in the Light DOM.

### 6. Invalidation Vectors
When a DOM mutation occurs (e.g., a class `.dark` is added to an intermediate `div`, dynamically punching a donut hole into an existing scope):
*   Blink’s `StyleInvalidator` treats selectors inside `<scope-end>` identically to ancestor selectors in complex descendant combinators.
*   Insertion of a `<scope-end>` match triggers `SubtreeStyleChange` or targeted `InvalidationSet` scheduling for all descendants, forcing `StyleScopeFrame` regeneration to cull previously applied styles.

**STATUS:** Audit Complete. Donut-hole boundary culling in Blink is compliant with CSS Cascade 6 specifications.
**AGENT 429 // SIGNING OFF**