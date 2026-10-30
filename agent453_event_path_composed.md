**AUDIT REPORT: Blink Event Path Calculation & Shadow Boundary Clipping**
**Auditor:** Agent 453
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/dom/events/`)
**Subject:** `Event::composedPath()` Traversal and Encapsulation Enforcement

---

### 1. Executive Summary
In Blink, `Event::composedPath()` generates the sequence of `EventTarget` nodes through which an event will propagate. To preserve Shadow DOM encapsulation, this path cannot simply return the raw flat-tree ancestor chain. Blink implements a multi-stage algorithm—primarily housed within `EventPath` and `TreeScope`—that pre-calculates the full propagation path at dispatch time and dynamically filters (clips) it when `composedPath()` is invoked based on the *context of the invoker* (primarily `currentTarget`).

---

### 2. Core Data Structures
The traversal and clipping mechanisms rely on three primary classes in Blink:

1. **`EventPath`**: Constructed when an event is dispatched. It builds an array of `NodeEventContext` objects representing the full, unclipped flat-tree ancestor chain from the `target` up to the `Window`.
2. **`NodeEventContext`**: Holds the specific `Node`, the retargeted `EventTarget` for that scope, and a pointer to its `TreeScopeEventContext`.
3. **`TreeScopeEventContext`**: Represents a specific DOM tree or Shadow Tree (`TreeScope`). It stores tree-level metadata, including `root_node_`, `target_` (retargeted), and a pre-calculated bitmask or relationship map used to quickly determine unclosed vs. closed trees relative to other scopes.

---

### 3. Phase 1: Full Path Construction & The `composed` Flag

Before `composedPath()` is ever called by JS, Blink initializes the `EventPath` during `EventDispatcher::Dispatch()`. 

#### The `composed: false` Hard Clip
If an event is initialized with `composed: false` (the default for many synthetic events and certain UI events like `mouseenter`), it is strictly forbidden from crossing the shadow boundary of the tree where it originated.

* **Blink Implementation:** During `EventPath::Initialize()`, Blink traverses up the flat tree via `LayoutTreeBuilderTraversal::Parent()` (or `FlatTreeTraversal::Parent()`). 
* When the traversal encounters a `ShadowRoot`, it checks `event.composed()`. 
* If `false`, **the traversal halts immediately**. The `ShadowRoot` is the final node added to the `EventPath`. The shadow host and all outer ancestor scopes are completely omitted from the underlying `NodeEventContext` vector.

---

### 4. Phase 2: Dynamic Path Clipping (`composed: true`)

When an event has `composed: true`, it traverses through the `ShadowRoot` into the `ShadowHost` and up to the Document/Window. However, `event.composedPath()` must still obscure nodes inside `mode: 'closed'` shadow roots if the caller does not have the authority to see them.

In Blink, this is evaluated lazily when `Event::composedPath(ScriptState*)` is called, utilizing `EventPath::CalculatePath()`.

#### The Authority Reference Point (`currentTarget`)
The visibility of a shadow tree is determined relative to the **root of the `currentTarget`**. 
*(Note: If `composedPath()` is called before or after dispatch when `currentTarget` is `null`, Blink uses the root of the ** originally dispatched `target`** as the reference point—unless the target itself was inside a closed shadow root relative to the script context, in which case the path returns empty `[]` after dispatch).*

#### The Clipping Rules (Shadow-Including Inclusive Ancestor)
Let **$T_{curr}$** be the `TreeScope` of `event.currentTarget`.
Let **$T_{node}$** be the `TreeScope` of a candidate node in the `EventPath`.

As Blink iterates through the `EventPath` to build the `HeapVector<Member<EventTarget>>` returned to V8, it evaluates the relationship between $T_{curr}$ and $T_{node}$:

1. **Upward Traversal (Ancestors of $T_{curr}$):**
   Any node in $T_{curr}$ or in an ancestor `TreeScope` (outer DOM trees) is **always included**. Even if $T_{curr}$ is inside a `closed` shadow root, a listener *inside* that closed root can see all the way up to the `Window` (assuming `composed: true`).

2. **Downward/Inward Traversal (Descendants of $T_{curr}$):**
   If $T_{node}$ is a descendant scope of $T_{curr}$ (meaning the event originated deeper in the tree and bubbled up to $T_{curr}$), Blink checks the `ShadowRoot` boundaries between $T_{node}$ and $T_{curr}$:
   * **Open Shadow Roots:** If $T_{node}$ is separated from $T_{curr}$ *only* by `mode: 'open'` shadow roots, the nodes in $T_{node}$ are **included**.
   * **Closed Shadow Roots:** If there is *any* `ShadowRoot` with `mode: 'closed'` in the ancestor chain between $T_{node}$ and $T_{curr}$, the entire subtree beneath that closed `ShadowRoot` is **clipped (omitted)**.

3. **Sibling Scopes (Slotted Content Hazard):**
   This is the most complex edge case in Blink's `TreeScopeEventContext`. When an element from the Light DOM is assigned to a `<slot>` inside a `closed` Shadow DOM, the flat-tree path goes:
   `SlottedNode (Light DOM)` $\rightarrow$ `Slot (Closed Shadow DOM)` $\rightarrow$ `ShadowRoot (Closed)` $\rightarrow$ `ShadowHost (Light DOM)`.
   * **Listener on `ShadowHost` (Light DOM):** $T_{curr}$ is the Light DOM. As Blink filters the path, it includes `SlottedNode` (because it belongs to $T_{curr}$), **clips/omits** `Slot` and `ShadowRoot` (because they are in a child $T_{node}$ marked `closed`), and includes `ShadowHost`.
   * **Listener on `Slot` (Closed Shadow DOM):** $T_{curr}$ is the Closed Shadow DOM. It includes `SlottedNode` (because Light DOM is an ancestor scope of $T_{curr}$), includes `Slot` and `ShadowRoot` (same scope as $T_{curr}$), and includes `ShadowHost` (ancestor scope). **Nothing is clipped.**

---

### 5. Blink Optimization: Pre-order / Post-order Tree Indexing

Doing naive parent-pointer walks to check for `closed` shadow roots on every node in `EventPath` would make `composedPath()` $O(N \times D)$ (where $N$ is path length and $D$ is tree depth). 

Blink optimizes this in `TreeScopeEventContext`:
1. During `EventPath` initialization, Blink builds a tree of `TreeScopeEventContext` objects mirroring the `TreeScope` hierarchy involved in the event.
2. It runs a depth-first traversal over these scopes, assigning **pre-order** and **post-order** tree numbers.
3. This allows $O(1)$ ancestor checks (`IsUnclosedTreeOf()`). If `TreeScope A` is an unclosed ancestor of `TreeScope B`, `B`'s pre-order index will fall strictly within `A`'s pre-order and post-order range, *except* where severed by a `ShadowRoot::IsOpen() == false` boundary, which resets or isolates the numbering context for visibility checks.

---

### 6. Audit Summary Table

Given an event (`composed: true`) originating at `#inner-btn` in the following flat tree:
`Window` $\rightarrow$ `Document` $\rightarrow$ `#host-open` $\rightarrow$ `#sr-open` $\rightarrow$ `#host-closed` $\rightarrow$ `#sr-closed` $\rightarrow$ `#slot` $\rightarrow$ `#slotted-light-div` (from `#host-open`'s scope) $\rightarrow$ `#inner-btn` (inside `#sr-closed`).

*(Wait: `#inner-btn` cannot be inside `#sr-closed` and also a child of `#slotted-light-div`. Correcting topology for audit accuracy: `#slotted-light-div` is in `#sr-open`, slotted into `#slot` inside `#sr-closed`.)*

**Topology:**
`#sr-open` contains `<#host-closed><#slotted-light-div></#host-closed>`.
`#sr-closed` contains `<#wrapper><#slot></#slot></#wrapper>`.
Event target is `#slotted-light-div`.

| Listener Location (`currentTarget`) | Resulting `event.composedPath()` | Audit Note |
| :--- | :--- | :--- |
| **`#slotted-light-div`** | `[#slotted-light-div, #host-closed, #sr-open, #host-open, Document, Window]` | `#slot`, `#wrapper`, and `#sr-closed` are **clipped** because they exist in a closed descendant scope relative to the target's scope (`#sr-open`). |
| **`#wrapper`** (inside `#sr-closed`) | `[#slotted-light-div, #slot, #wrapper, #sr-closed, #host-closed, #sr-open, #host-open, Document, Window]` | **Unclipped.** A closed tree has full visibility of itself and its ancestor scopes (including nodes slotted *from* ancestor scopes). |
| **`Document`** | `[#slotted-light-div, #host-closed, #sr-open, #host-open, Document, Window]` | `Document` can see into `#sr-open` (hence it sees `#slotted-light-div` and `#host-closed`), but `#sr-closed` and its internal nodes (`#wrapper`, `#slot`) are **clipped**. |
| **`null`** (Async / Post-dispatch) |*(Depends on original target)* <br>Here: `[#slotted-light-div, #host-closed, #sr-open, #host-open, Document, Window]` |Evaluated relative to the initial `target` (`#slotted-light-div`). If the initial target had been `#wrapper` (inside closed), calling `composedPath()` asynchronously from `Document` context would clip the nodes inside `#sr-closed`. |

**End of Report.**