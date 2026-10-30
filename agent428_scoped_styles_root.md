**Audit Report: Blink `@scope` Root Matching & Subtree Containment Verification**
**Auditor:** Agent 428
**Target:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/css/`)
**Subject:** CSS Cascading and Inheritance Level 6 (`@scope`) — Subtree Containment Mechanics

---

### 1. Executive Summary
In Blink, `@scope` subtree containment verification ensures that a style rule applies only if the target element resides within the inclusive descendant subtree of a matched `<scope-start>` element, and strictly outside the inclusive descendant subtree of any `<scope-end>` element associated with that specific scope root. 

Verification is handled dynamically during style resolution via `StyleScopeFrame` and `ElementRuleCollector`, with flat-tree traversal bounds enforced by `SelectorChecker`.

### 2. Core Data Structures

*   **`StyleScope` (`style_scope.h`)**: Represents the AST/parsed data of an `@scope` rule, holding the `from_` (`CSSSelectorList` for `<scope-start>`) and `to_` (`CSSSelectorList` for `<scope-end>`) selectors, alongside the pointer to the parent `StyleScope` (for nested `@scope` rules).
*   **`StyleScopeFrame` (`style_scope_frame.h`)**: A stack-allocated (Oilpan `STACK_ALLOCATED()`) caching structure instantiated during the style recalc tree walk (`Element::RecalcStyle`). Each frame corresponds to an `Element` being styled and holds a reference to its parent element's `StyleScopeFrame`. It caches active `StyleScopeActivation` instances for a given `StyleScope` to avoid redundant O(N²) ancestor walks.
*   **`StyleScopeActivation`**: Represents a verified scope root. It pairs a `const Element* root` with the specific `unsigned proximity` (number of flat-tree hops from the subject element to the `root`).

### 3. Subtree Containment Verification Pipeline

When `ElementRuleCollector` evaluates a `RuleData` entry belonging to a `StyleScope`, it invokes `SelectorChecker` to verify both the rule's selector and its `@scope` activations.

#### Phase A: Scope Root Discovery (The `<scope-start>` Walk)
To verify if the current `Element` (the subject) is contained within a valid scope root, Blink must find all active roots in the ancestor chain.

1.  **Frame Lookup**: `SelectorChecker::CheckStyleScope` queries the current `StyleScopeFrame` for the `StyleScope`.
2.  **Ancestor Traversal**: If the activations for this `StyleScope` are not cached in the current frame, Blink walks up the `StyleScopeFrame` parent pointers (which mirrors the **Flat Tree** ancestor chain via `LayoutTreeBuilderTraversal::ParentElement`).
3.  **Outer Scope Dependency**: If the `StyleScope` is nested inside an outer `@scope`, the outer `StyleScope` is evaluated first. A candidate element can only be a root for an inner `@scope` if it is within the active subtree of the outer `@scope`.
4.  **Root Matching**: At each ancestor (and the subject element itself, as scope roots are inclusive), `SelectorChecker` evaluates the `StyleScope::From()` selector list:
    *   *Implicit Root:* If `From()` is omitted (`@scope { ... }`), the root is implicitly the parent `Node` of the `HTMLStyleElement` owning the stylesheet. Containment is verified by checking pointer equality against this `Node` during the upward walk.
    *   *Explicit Root:* `SelectorChecker::Match` is run against the candidate element using the `From()` selector.

#### Phase B: Limit Enforcement (The `<scope-end>` Truncation)
Subtree containment is invalidated if an element is at or below a `<scope-end>` boundary. Because a single `<scope-start>` subtree can contain multiple `<scope-end>` elements, and `<scope-start>` elements can nest, limit verification is strictly tied to the specific `StyleScopeActivation` being propagated down the `StyleScopeFrame` stack.

1.  **Downward Propagation / Upward Caching**: As `CalculateActivations` recurses up the `StyleScopeFrame` chain and returns down toward the subject element, it inherits the `StyleScopeActivation` vector from the parent frame.
2.  **Proximity Increment**: For every step down the tree from an established root, the `proximity` counter for each inherited activation is incremented by `1`.
3.  **Limit Matching (`SeeingEndOfScope`)**: At the current element, before accepting the inherited activations (and any newly matched activation on the current element itself), Blink checks `StyleScope::To()`.
4.  **Scoped `:scope` Binding**: When evaluating the `To()` selector list on the current element, the `:scope` pseudo-class (and implicit `&` context) must resolve to the specific `activation.root` currently being tested. `SelectorChecker::SelectorCheckingContext` sets `context.scope = activation.root`.
5.  **Culling**: If the current element matches the `To()` selector for a specific `activation.root`, that specific `StyleScopeActivation` is **dropped** (truncated) from the current frame's activation list. 
    *   *Audit Note:* Because `<scope-end>` is *exclusive* (a scope limit is not in the scope), dropping the activation on the matching element prevents the rule from matching the limit element itself and any of its descendants (since child frames pull from this frame's truncated list).

#### Phase C: Subject Rule Matching Within the Subtree
Once `StyleScopeFrame` yields a non-empty vector of valid `StyleScopeActivation` structs for the subject element, subtree containment is confirmed. However, the subject's own CSS selector must still be checked *relative* to those roots.

1.  **Activation Iteration**: `SelectorChecker` iterates through the active `StyleScopeActivation` list (ordered from innermost/lowest proximity to outermost/highest proximity).
2.  **Context Binding**: For each activation, `SelectorCheckingContext::scope` is bound to `activation.root`.
3.  **Combinator Boundary Enforcement**: As `SelectorChecker` walks up the tree from the subject to match ancestor combinators (e.g., `.a .b`), it does **not** hard-stop at `activation.root` by default (per CSS Cascading 6, selectors inside `@scope` are not automatically `:scope` contained unless `:scope` or `&` is explicitly or implicitly prepended). *However*, Blink's parser implicitly prepends `:scope` (or marks the selector with `kRelationIsScopeActivation`) to scoped selectors that do not explicitly contain `:scope` or `&`.
4.  **Activation Relation (`CSSSelector::kScopeActivation`)**: When `SelectorChecker` encounters the injected `kScopeActivation` relation in the selector chain, it jumps/binds the current matching element directly to `context.scope` (`activation.root`), verifying that the top of the selector chain is anchored within or at the scope root.
5.  **Cascade Proximity Recording**: The first activation in the list that successfully satisfies the full selector sets `MatchResult::proximity` to `activation.proximity`. Because the activations are sorted by proximity ascending, the first match guarantees the minimum proximity value for the CSS Cascade (where lower proximity wins).

### 4. Edge Case & Invalidation Verification

*   **Shadow DOM / Flat Tree**: `StyleScopeFrame` parent pointers strictly follow the Flat Tree. If an `@scope` rule is defined inside a Shadow Tree, or targets slotted content, `SelectorChecker` respects `TreeScope` boundaries unless `:host` or `::slotted` are explicitly involved, preventing scope leakage across shadow boundaries while maintaining correct containment for distributed nodes.
*   **Dynamic DOM Mutations**: Subtree containment relies on `StyleEngine` invalidation sets. Mutating an attribute that causes an intermediate ancestor to newly match `<scope-end>` triggers `SubtreeStyleChange` or targeted invalidation sets generated from the `To()` selector, forcing reconstruction of the `StyleScopeFrame` chain during the next lifecycle update.

**Status:** Subtree containment logic in Blink conforms to the W3C CSS Cascading and Inheritance Level 6 specification. No containment leaks detected. **Agent 428 signing off.**