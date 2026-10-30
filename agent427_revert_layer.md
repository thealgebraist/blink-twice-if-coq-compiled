**AUDIT LOG: BLINK RENDERING ENGINE (CHROMIUM)**
**AUDITOR:** Agent 427
**TARGET:** CSS `revert-layer` Keyword Implementation
**COMPONENT:** `third_party/blink/renderer/core/css/resolver/`

---

### 1. Executive Summary
The `revert-layer` CSS keyword rolls back a property’s cascaded value to the value established in the previous cascade layer, or to the previous style origin if no prior layer exists within the current origin. In Blink, this requires retaining historical declaration data during the `MatchResult` collection phase and performing a backward stack traversal during the `StyleCascade` application phase.

### 2. Core Data Structures
Blink does not build a literal Linked List stack per property. Instead, it relies on a flattened, ordered array of matched declarations and traverses it backward.

*   **`MatchResult`**: Populated by `ElementRuleCollector`. Contains `Vector<MatchedProperties>`.
*   **`MatchedProperties`**: Contains a `CSSPropertyValueSet` and metadata (`Data`), which includes:
    *   `CascadeOrigin` (UserAgent, User, Author, Animation, Transition).
    *   `layer_order` (`uint16_t`): Numeric identifier calculated by `CascadeLayerMap` representing the topological sort of `@layer` rules. Unlayered styles within an origin implicitly receive the highest `layer_order` (`kImplicitOuterLayerOrder`).
*   **`CascadeMap`**: A fast-lookup hash map/tree (`CascadePriority` indexed by `CSSPropertyID`) maintained by `StyleCascade`. It stores the *winning* priority for each property.
*   **`CascadePriority`**: A 64-bit bitfield packing `CascadeOrigin`, `is_important`, `tree_order` (Shadow DOM), `layer_order`, and `position` (index into `MatchResult` declarations).

### 3. Stack Traversal Mechanism (The Rollback)

When `StyleCascade::Apply()` resolves styles, it uses a `CascadeResolver`. If a property resolves to a `CSSValue` with `IsRevertLayerValue()`, Blink initiates a rollback traversal instead of applying the value.

#### Phase A: The Trigger
1. `StyleCascade::LookupAndApplyDeclaration()` reads the winning `CascadePriority` from the `CascadeMap`.
2. It extracts the `CSSValue`. Seeing `cssvalue::CSSRevertLayerValue`, it aborts standard application and invokes `StyleCascade::ResolveRevertLayer()`.

#### Phase B: Defining the Rollback Threshold
To roll back, Blink must determine what "previous layer" means in the context of the CSS Cascade (specifically accounting for the `!important` inversion).

Let $P_{current}$ be the `CascadePriority` of the declaration containing `revert-layer`.
Blink constructs a target comparison priority by stripping the current layer's dominance. 

The traversal looks for a declaration with priority $P_{candidate}$ that satisfies:
*   Same or lower `CascadeOrigin` (after accounting for `!important` origin inversion).
*   If in the **same** `CascadeOrigin` and **same** `tree_order`:
    *   For **Normal** rules: $P_{candidate}.\text{layer\_order} < P_{current}.\text{layer\_order}$
    *   For **`!important`** rules: Because lower layers win in `!important`, `CascadePriority` inverts the bits of `layer_order` during construction. Thus, the bitwise comparison remains strictly $P_{candidate} < P_{current}$ with a different `layer_order`.

#### Phase C: Backward Array Traversal (`FindRevertLayer`)
Because `CascadeMap` only overwrites and retains the *single* highest priority for a property, the runner-up values are lost from the map. Blink must re-scan the `MatchResult` to find the fallback value.

1. **Initialization**: Traversal starts at the declaration index (`position`) encoded in $P_{current}$ and iterates backward toward index `0` of the `MatchResult` declarations array.
2. **Filtering**: For each declaration in the backward pass:
   * Does the declaration define the target `CSSPropertyID` (or a shorthand encompassing it)? If no, `continue`.
   * Generate $P_{candidate}$ for this declaration.
   * **Layer Check**: Compare $P_{candidate}$ against $P_{current}$'s layer context. 
     * If $P_{candidate}$ belongs to the *exact same* cascade layer, tree scope, and importance as $P_{current}$, it is **ignored** (we are reverting the *entire* layer, not just the rule).
     * If $P_{candidate}$ has a higher priority than $P_{current}$ (possible due to out-of-order `MatchResult` insertion from Shadow DOM or `!important`), it is **ignored**.
3. **Selection**: Blink tracks the highest $P_{candidate}$ found that is strictly less than the current layer's priority boundary.

*(Note: Unlike a naive stack pop, a full scan of prior matched properties is often required because `!important` declarations and Shadow DOM (`tree_order`) declarations are not strictly sorted in final cascade order within the raw `MatchResult` vector).*

#### Phase D: Resolution & Chaining
Once the backward traversal completes:

*   **Case 1: Fallback Found in Previous Layer.** 
    The declaration with the highest valid $P_{candidate}$ is returned. 
*   **Case 2: Chained `revert-layer`.** 
    If the newly found fallback declaration *also* has the value `revert-layer`, the loop continues recursively (or iteratively updates $P_{current} = P_{candidate}$) and continues scanning backward.
*   **Case 3: Layer Exhaustion (Origin Fallback).** 
    If no prior `@layer` exists in the Author origin, the backward scan naturally crosses the boundary into `CascadeOrigin::kUser` or `CascadeOrigin::kUserAgent` (which exist at lower indices in `MatchResult`). The behavior seamlessly degrades to that of the `revert` keyword.
*   **Case 4: Total Exhaustion.** 
    If the traversal reaches index `0` (User Agent styles) and finds no matching property, the function returns `nullptr`. `StyleBuilder` then applies the property's `initial` or `inherited` value (behaving like `unset`).

### 4. Edge Cases Audited

*   **Implicit Outer Layer**: Rules not wrapped in `@layer` are assigned `kImplicitOuterLayerOrder` (effectively `UINT16_MAX`). Using `revert-layer` in an unlayered style successfully rolls back to the highest-ordered explicit `@layer`.
*   **Logical Properties & Shorthands**: During the backward traversal, `CSSPropertyID` matching accounts for physical-to-logical mappings (e.g., `margin-left` vs `margin-inline-start`). `CascadeResolver` resolves the writing mode *before* the cascade, allowing the backward scan to match aliased/mapped properties accurately.
*   **Animations/Transitions**: `CascadeOrigin::kAnimation` and `kTransition` do not support layers. If `revert-layer` is somehow injected there, it reverts to the Author origin.

### 5. Audit Conclusion
Blink's implementation of `revert-layer` avoids memory bloat in the common case (no `revert-layer` used) by keeping `CascadeMap` flat (O(1) memory per property). It trades this for an O(N) backward scan of `MatchResult` (where N is the number of matched rules on the element) *only* when `revert-layer` is actively encountered. Given that N is typically small per element, this is an optimal architectural tradeoff. 

**STATUS:** Implementation verified. Compliant with CSS Cascading and Inheritance Level 5. 
**END LOG.**