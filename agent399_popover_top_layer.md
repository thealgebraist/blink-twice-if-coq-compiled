**AUDIT REPORT: BLINK RENDERING ENGINE**
**Auditor:** Agent 399
**Target Subsystem:** HTML Popover API / CSS Top Layer Stacking Context (`third_party/blink/renderer/core/dom/document.cc`, `html_element.cc`, `layout_view.cc`)
**Subject:** Strict Top Layer Monotonicity Verification

---

### 1. Executive Summary & Definition
In the Blink rendering engine, **Strict Top Layer Monotonicity** is the invariant that dictates the visual painting and hit-testing order of elements promoted to the browser's `top layer` (such as Popovers, Modal Dialogs, and Fullscreen elements). 

Because the top layer completely bypasses the standard CSS stacking context tree, traditional `z-index` values, DOM tree order, and ancestor `opacity`/`transform` stacking contexts are nullified. Instead, the top layer relies on a strict **First-In, First-Out (FIFO) insertion-order vector** that acts as a **Last-In, First-Out (LIFO) visual stack**. 

"Strict Monotonicity" means that for any index $i$ and $j$ in the `Document::top_layer_elements_` vector:
$$\text{If } i < j, \text{ then } \text{PaintOrder}(Element_i) < \text{PaintOrder}(Element_j)$$
$Element_j$ is strictly painted *over* $Element_i$, and will intercept pointer events before $Element_i$, regardless of where $Element_i$ and $Element_j$ reside in the standard DOM tree.

---

### 2. Blink Data Structure Architecture
In Blink, top layer monotonicity is maintained at the `Document` level via a single source of truth:

```cpp
// third_party/blink/renderer/core/dom/document.h
HeapVector<Member<Element>> top_layer_elements_;
```

*   **Insertion (`AddToTopLayer`):** When `showPopover()` is invoked, Blink ensures the element is not already in the vector (or removes it first if re-ordering is triggered), and appends it via `top_layer_elements_.push_back(element)`.
*   **Removal (`RemoveFromTopLayerImmediately`):** When `hidePopover()` is completed (post-transition), the element is spliced out via `top_layer_elements_.EraseAt(index)`. The relative order of all remaining elements is strictly preserved.

---

### 3. Monotonicity Rules for Popovers

During the audit of `HTMLElement::ShowPopoverInternal`, the following rules govern how popovers interact with the monotonic stack:

#### A. The Promotion Invariant
When a `popover` transitions from the `hidden` state to the `showing` state, it is appended to the very end of `top_layer_elements_`. It is guaranteed to render on top of all previously opened popovers, modal `<dialog>` elements, and fullscreen elements currently in the stack.

#### B. Nested `popover="auto"` Stack Discipline
Auto popovers enforce a strict hierarchical tree structure (via implicit anchor references, `popovertarget` invokers, or DOM nesting) alongside the top layer stack:
1. If Popover A is open at index $i$, and triggers child Popover B, Popover B is inserted at $i+1$.
2. Because `popover="auto"` enforces light-dismissal of non-ancestors, you cannot violate monotonicity by opening an unrelated Popover C without first collapsing B and A (removing them from the vector).
3. Thus, the `auto` popover stack is strictly monotonic both in **visual stacking** and **logical ancestry**.

#### C. `popover="manual"` and `popover="hint"` Interleaving
Manual popovers do not participate in the `auto` dismissal stack. 
*   If Manual Popover M1 opens (Index 0), followed by Auto Popover A1 (Index 1), followed by Manual Popover M2 (Index 2), the paint order is strictly `M1 -> A1 -> M2`.
*   If A1 now opens child Auto Popover A2, A2 is appended at Index 3.
*   **Audit Note:** Even though A2 is a logical child of A1, it paints *above* M2 because A2 entered the top layer *after* M2. Monotonicity of time-of-entry supersedes logical popover ancestry.

#### D. No Re-Promotion on Redundant Calls
Calling `showPopover()` on an *already showing* popover is a no-op (or throws an `InvalidStateError` depending on the call site). An author cannot mutate the monotonic order of open popovers without first calling `hidePopover()` and `showPopover()`, which destroys and recreates the top layer entry (and resets state/focus).

---

### 4. Edge Cases & Pseudo-Element Sub-Stacking

To verify strict monotonicity, Agent 399 audited the rendering pipeline in `BoxPaintInvalidator` and `PaintLayerStackingNode`. Two critical nuances exist within the stack:

#### 1. The `::backdrop` Sub-Ordering
Every element in `top_layer_elements_` may generate a `::backdrop` pseudo-element. The `::backdrop` does not occupy a separate index in the `top_layer_elements_` C++ vector, yet it participates in top layer painting.
For a given element at index $i$:
$$\text{PaintOrder}(Element_{i-1}) < \text{PaintOrder}(Backdrop_i) < \text{PaintOrder}(Element_i)$$
Monotonicity is preserved by binding the backdrop's stacking context directly below its owning element, but strictly above index $i-1$.

#### 2. CSS Transitions and the "To-Be-Removed" State
When `hidePopover()` is called, a popover may have a CSS transition applied to `overlay` or `display` (`transition-behavior: allow-discrete`). 
*   During the transition, the element must remain visible in the top layer, so it **remains in `top_layer_elements_`** at its current index $i$ to preserve visual monotonicity while fading out.
*   Blink tracks these in a separate set: `elements_with_pending_top_layer_removal_`.
*   **Re-entry Edge Case:** If `showPopover()` is called on that same element *while* it is still transitioning out, Blink aborts the removal, pulls it out of index $i$, and **re-appends it to the end of `top_layer_elements_`**. It loses its old slot and becomes the newest, topmost element.

---

### 5. Interaction with Other Top-Layer Citizens

The top layer is shared by three APIs: Fullscreen, `<dialog>` (`showModal()`), and Popover. 
*   **Dialog vs. Popover:** A modal dialog opened *after* a manual popover will sit at a higher index and paint over the popover (and trap focus, making the popover inert, though still visually behind the dialog's backdrop). A popover opened *from inside* a modal dialog will be appended after the dialog, painting on top of it.
*   **Fullscreen Collision:** If `requestFullscreen()` is called, the fullscreen element is pushed to the back of `top_layer_elements_`. Note that fullscreen activation triggers light-dismissal of `auto` popovers, purging them from the vector, while `manual` popovers remain in the vector—trapped visually *underneath* the newly promoted fullscreen element unless they are hidden and re-shown.

---

### 6. Audit Verdict
**STATUS: COMPLIANT.**
Blink's implementation of the Popover top layer strictly adheres to temporal monotonicity. Layout and Paint phases iterate forward through `Document::TopLayerElements()`, ignoring CSS `z-index` mutations on top-layer roots, ensuring deterministic, spec-compliant LIFO occlusion and hit-testing. 

*End of Audit — Agent 399.*