**AUDIT REPORT: BLINK SHADOW DOM ENCAPSULATION**
**AUDITOR:** Agent 451
**TARGET:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/dom/`)
**SUBJECT:** Shadow Boundary Isolation & Encapsulation Mechanics

---

### 1. EXECUTIVE SUMMARY
The Shadow Boundary in Blink is the architectural barrier separating the primary Document tree (Light DOM) from a component's internal subtree (`ShadowRoot`). Isolation is enforced primarily through the `TreeScope` abstraction, event path retargeting, and scoped CSS style resolution. 

### 2. DOM TREE & TRAVERSAL ISOLATION
At the C++ level, Blink prevents accidental traversal across the shadow boundary by segregating nodes into distinct scopes while maintaining a unified flat tree for rendering.

*   **`TreeScope` Separation:** Both `Document` and `ShadowRoot` inherit from `TreeScope`. Every `Node` holds a pointer to its owning `TreeScope`. APIs such as `querySelector`, `getElementById`, and ID reference resolution (e.g., `aria-labelledby`) are strictly bound to the `TreeScope` of the context object.
*   **Pointer Nullification:** Standard DOM traversal properties (`parentNode`, `parentElement`, `nextSibling`) return `nullptr` when attempting to traverse upward from a `ShadowRoot` to its `ElementShadow` host, or downward from the host into the shadow tree.
*   **`FlatTreeTraversal` vs. `NodeTraversal`:** 
    *   `NodeTraversal` is exposed to JavaScript and strictly respects the shadow boundary.
    *   `FlatTreeTraversal` is used internally by Blink for Layout, Paint, and Accessibility. It resolves `<slot>` assignments (`SlotAssignmentEngine`) to create a unified tree, completely opaque to unprivileged script execution.
*   **Mode Enforcement (`open` vs. `closed`):** Implemented via `ShadowRoot::GetType()`. If `kClosed`, `Element::shadowRoot()` returns `nullptr` to V8 bindings, though internal C++ pointers (`Element::GetShadowRoot()`) remain intact for engine operations.

### 3. EVENT MODEL & RETARGETING
Events must cross the shadow boundary to allow the host document to respond to user interactions, but they must not leak internal node references. This is handled by `EventPath` and `EventDispatcher`.

*   **Event Path Calculation:** When an event is dispatched, Blink calculates the full path across the flat tree, storing contexts in `TreeScopeEventContext`.
*   **Retargeting (`Event.target`):** As an event bubbles up and crosses a `ShadowRoot` boundary into an outer `TreeScope`, Blink rewrites the `target` property to reference the **Shadow Host** rather than the internal originating node.
*   **Composed Events:** Events feature a `composed` boolean flag. 
    *   `composed: false` (e.g., `mouseenter`, `load`, custom events by default): Execution halts at the `ShadowRoot` boundary.
    *   `composed: true` (e.g., `click`, `focus`, `input`): The event crosses the boundary and undergoes retargeting.
*   **`composedPath()` Filtering:** When `Event.prototype.composedPath()` is invoked, Blink filters the internal `EventPath`. Nodes belonging to a `closed` `ShadowRoot` that is not an ancestor of the current target's `TreeScope` are omitted from the returned array.
*   **RelatedTarget Retargeting:** For events like `mouseover` or `focusin`, if both `target` and `relatedTarget` resolve to the *same* Shadow Host after retargeting in the outer scope, Blink suppresses the event dispatch in the outer scope entirely to prevent nonsensical self-transition events.

### 4. CSS & STYLE ENCAPSULATION
Style isolation ensures that outer stylesheets do not inadvertently mutate shadow trees, and internal styles do not bleed out. Managed by `StyleEngine` and `ScopedStyleResolver`.

*   **`ScopedStyleResolver`:** Each `ShadowRoot` maintains its own `ScopedStyleResolver`. Selector matching (`ElementRuleCollector`) only evaluates rules registered within the node's immediate `TreeScope`.
*   **Inheritance vs. Selector Matching:** The shadow boundary blocks **selector matching**, not **property inheritance**. Inherited CSS properties (`color`, `font-family`, CSS Custom Properties/`--vars`) naturally cascade across the boundary via the `ComputedStyle` resolution on the Flat Tree.
*   **Controlled Bleed Mechanisms:**
    *   `:host` and `:host-context()`: Allow the `ShadowRoot` to style its own host element, evaluated with lower specificity than rules defined in the outer Light DOM.
    *   `::slotted()`: Allows a `ShadowRoot` to style top-level nodes distributed into a `<slot>`, crossing the boundary back into the Light DOM in a strictly limited capacity.
    *   `::part()`: Allows the outer `TreeScope` to style specific internal shadow nodes explicitly exported via the `part` attribute, mapped via `PartNames`.

### 5. FOCUS & SELECTION ISOLATION
*   **`DocumentOrShadowRoot.activeElement`:** Focus is recursive. If an input inside a shadow tree is focused, `document.activeElement` returns the Shadow Host. Querying `shadowRoot.activeElement` returns the actual input (or the next nested Shadow Host).
*   **Selection API:** `window.getSelection()` struggles with shadow boundaries. Blink implements shadow-aware selection adjustment: if a user's selection crosses a shadow boundary, standard `Range` APIs exposed to JS will collapse or clamp the range endpoints to the boundary (the Shadow Host) to prevent leaking internal `Node` references, while internal `SelectionInDOMTree` tracks the true flat-tree endpoints for rendering the highlight.

### 6. KNOWN AUDIT VECTORS (POTENTIAL LEAK SURFACES)
When auditing Blink for encapsulation bypasses (CVEs), Agent 451 monitors the following high-risk subsystems:
1.  **V8 Wrapper Generation:** Ensuring C++ methods returning internal `Node*` pointers (e.g., hit-testing APIs like `elementFromPoint`) pass through `TreeScope::Retarget()` before returning to V8.
2.  **MutationObserver:** Ensuring `MutationObserver` instances attached to a Light DOM node do not receive `MutationRecord` deliveries for changes occurring strictly inside a child's `ShadowRoot`.
3.  **Slotted Node Re-distribution:** Use-After-Free (UAF) or state-mismatch bugs in `SlotAssignmentEngine` during rapid DOM mutations coupled with synchronous layout/style recalculations.

**STATUS:** Encapsulation boundaries functioning within expected parameters. End of report.