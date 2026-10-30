**Audit Report: Blink View Transitions Pseudo-Element Tree Nesting**
**Agent:** 431
**Target:** Chromium / Blink Rendering Engine (`blink::ViewTransition`, `blink::ViewTransitionStyleTracker`)

In the Blink rendering engine, the View Transition API constructs a dynamic tree of pseudo-elements to render capturing and animating states. This tree is injected as a sibling to the document element's layout object, positioned at the very top of the stacking context ( residing in the "top layer" alongside `<dialog>` and Fullscreen elements), hanging directly off the originating `<html>` (`documentElement`) element.

Here is the detailed specification of the View Transition pseudo-element tree nesting and its internal Blink architecture.

---

### 1. The Pseudo-Element Hierarchy Tree

The nesting strictly follows a four-tier hierarchy. For every element assigned a unique `view-transition-name` (plus the default `root`), Blink generates a corresponding branch inside the root pseudo-element.

```text
html (Originating Element)
└── ::view-transition
    ├── ::view-transition-group(root)
    │   └── ::view-transition-image-pair(root)
    │       ├── ::view-transition-old(root)
    │       └── ::view-transition-new(root)
    │
    └── ::view-transition-group(<view-transition-name>)
        └── ::view-transition-image-pair(<view-transition-name>)
            ├── ::view-transition-old(<view-transition-name>)
            └── ::view-transition-new(<view-transition-name>)
```

---

### 2. Detailed Node Audit

#### Tier 1: `::view-transition`
*   **Blink Internal ID:** `kPseudoIdViewTransition`
*   **Parent:** `document.documentElement` (`<html>`).
*   **Children:** Zero or more `::view-transition-group()` pseudo-elements.
*   **Role & Layout:** Acts as the root container for the entire transition overlay. In Blink's UA stylesheet, it is `position: fixed; inset: 0;` and placed in the Top Layer, ensuring it intercepts or overlays all standard DOM rendering.

#### Tier 2: `::view-transition-group(<name>)`
*   **Blink Internal ID:** `kPseudoIdViewTransitionGroup`
*   **Parent:** `::view-transition`
*   **Children:** Exactly one `::view-transition-image-pair(<name>)`.
*   **Role & Layout:** This node is responsible for geometry and positioning. Blink's `ViewTransitionStyleTracker` dynamically injects a UA stylesheet that animates this element's `width`, `height`, `transform` (matrix3d), and `writing-mode` from the "old" state bounds to the "new" state bounds. 

#### Tier 3: `::view-transition-image-pair(<name>)`
*   **Blink Internal ID:** `kPseudoIdViewTransitionImagePair`
*   **Parent:** `::view-transition-group(<name>)`
*   **Children:** 
    *   Zero or one `::view-transition-old(<name>)`
    *   Zero or one `::view-transition-new(<name>)`
*   **Role & Layout:** Exists strictly to provide a `isolation: isolate` stacking context (`position: absolute; inset: 0;`). This isolation is required so that the `mix-blend-mode: plus-lighter` applied to the child `old` and `new` states executes a true cross-fade without blending into the underlying page backdrop.

#### Tier 4: `::view-transition-old(<name>)` & `::view-transition-new(<name>)`
*   **Blink Internal IDs:** `kPseudoIdViewTransitionOld`, `kPseudoIdViewTransitionNew`
*   **Parent:** `::view-transition-image-pair(<name>)`
*   **Children:** None (Leaf nodes).
*   **Role & Layout:** These are **Replaced Elements** (`LayoutViewTransitionContent` in Blink). 
    *   `old` holds a static snapshot texture (`viz::ViewTransitionElementResourceId`) captured by the Viz compositor prior to DOM mutation.
    *   `new` holds a live representation texture of the updated DOM element.
*   **Conditional Rendering (Entry/Exit):**
    *   **Entry Transition:** If an element exists only in the new DOM, `::view-transition-old` is **omitted** from the tree.
    *   **Exit Transition:** If an element existed only in the old DOM, `::view-transition-new` is **omitted** from the tree.

---

### 3. Blink Implementation Specifics (Audit Notes)

*   **Tree Traversal:** Standard DOM traversal APIs ignore these elements. Within Blink, they are traversed via `PseudoElement` pointers managed by `ElementRareDataVector` on the `documentElement`.Nested traversal is handled by specialized logic in `PseudoElement::Dispose` and `StyleEngine` recalculations.
*   **Layout Object Generation:** `LayoutTreeBuilderForElement` bypasses standard DOM children attachment and relies on `ViewTransition::CreatePseudoElement` to instantiate the nested `PseudoElement` instances (`ViewTransitionPseudoElementBase` subclasses) on demand during style recalc.
*   **Painting & Compositing:** Because `old` and `new` are backed by Viz compositor surfaces, Blink suppresses normal painting of the real DOM elements (via `PaintLayer` flags) while the `::view-transition-new` leaf node is active, preventing double-rendering.

**End of Audit.**