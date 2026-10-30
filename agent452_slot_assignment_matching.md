**AUDIT REPORT: Blink Engine - HTMLSlotElement Name Matching Logic**
**Auditor:** Agent 452
**Target Subsystem:** `third_party/blink/renderer/core/dom/slot_assignment.cc` & `html_slot_element.cc`
**Status:** Active Analysis

---

### 1. Executive Summary
In the Blink rendering engine, slot assignment is managed lazily by the `SlotAssignment` class, owned by the `ShadowRoot`. The matching logic relies on `AtomicString` normalization and O(1) hash map lookups to bind light DOM nodes (slottables) to `HTMLSlotElement` instances within the shadow tree.

---

### 2. Name Normalization Logic
Before matching occurs, Blink normalizes the `name` attribute of the `<slot>` and the `slot` attribute of the child node into an internal `AtomicString`. This is handled by `HTMLSlotElement::NormalizeSlotName`.

*   **Null or Empty Values:** If an attribute is missing (`null_atom`) or explicitly set to an empty string (`""`), it is normalized to `g_empty_atom`. 
*   **Whitespace:** Whitespace is **not** trimmed. `<slot name=" ">` and `<div slot=" ">` will match each other, not the default slot.
*   **Case Sensitivity:** Matching is strictly case-sensitive (Code point-for-code point comparison).

**Normalization Matrix:**
| DOM State | Blink `AtomicString` Representation | Target Slot |
| :--- | :--- | :--- |
| `<div>` (No `slot` attr) | `g_empty_atom` | Default Slot |
| `<div slot="">` | `g_empty_atom` | Default Slot |
| `<slot>` (No `name` attr) | `g_empty_atom` | Default Slot |
| `<slot name="">` | `g_empty_atom` | Default Slot |
| `<div slot="foo">` | `"foo"` | `<slot name="foo">` |
| `TextNode` | `g_empty_atom` | Default Slot |

---

### 3. The Matching Algorithm (`SlotAssignment::AssignSlots`)
When `ShadowRoot` assignment is marked dirty (via DOM mutations or attribute changes), `SlotAssignment::RecalcAssignment()` triggers the matching pipeline.

#### Phase A: Slot Map Construction
Blink maintains a `HeapHashMap<AtomicString, Member<TreeOrderedList>>` representing the available slots in the `ShadowRoot`.
1.  All `<slot>` elements in the shadow tree are registered.
2.  **Duplicate Slot Names:** If multiple `<slot>` elements share the same normalized `AtomicString` name, they are stored in a `TreeOrderedList`.
3.  During matching, Blink resolves to the **first** `<slot>` in tree-order (pre-order, depth-first traversal). Subsequent slots with the same name remain unassigned unless the preceding slot is removed or renamed.

#### Phase B: Slottable Iteration & Resolution
Blink iterates through the **direct children** of the Shadow Host (`NodeTraversal::ChildrenOf(host)`).

1.  **Slottable Validation:** Blink checks `Node::IsSlottable()`. 
    *   *Valid:* `Element` and `Text` nodes.
    *   *Invalid (Ignored):* `Comment`, `ProcessingInstruction`, `DocumentType`.
2.  **Key Extraction:**
    *   If the node is an `Element`, Blink fetches `element.FastGetAttribute(html_names::kSlotAttr)`.
    *   If the node is a `Text` node, it lacks attributes and is implicitly assigned `g_empty_atom`.
3.  **Hash Lookup:**
    *   Blink queries the Slot Map using the normalized `AtomicString` key.
    *   **Match Found:** The node is appended to the `assigned_nodes_` vector of the first `HTMLSlotElement` in the `TreeOrderedList` for that key.
    *   **No Match Found:** The node is dropped from the flat tree (it is not rendered). It does **not** fall back to the default slot.

---

### 4. Imperative Slotting Override (Manual Mode)
*Audit Note: Blink supports Imperative Shadow DOM (`ShadowRoot.slotAssignment = "manual"`).*

If the `ShadowRoot` is initialized with `slotAssignment: 'manual'`, the name-matching logic detailed in Section 3 is **completely bypassed**.
*   `SlotAssignment::AssignSlots()` branches to `AssignToManualSlots()`.
*   `name` and `slot` attributes are ignored.
*   Matching is dictated strictly by the `HTMLSlotElement:: assign()` API, which stores weak references to candidate nodes in `HTMLSlotElement::manually_assigned_nodes_`.
*   Validation only checks if `candidate->parentNode() == shadow_root->host()`.

---

### 5. Edge Cases & Mutation Triggers
Blink optimizes slot recalculation by hooking into specific DOM lifecycle events:

*   **Dynamic Attribute Changes:** Modifying `<div slot="a">` to `<div slot="b">` triggers `Element::AttributeChanged`. If the parent is a Shadow Host, it calls `ShadowRoot::DidChangeHostChildSlotName`, setting the `needs_assignment_recalc_` flag.
*   **Slot Renaming:** Modifying `<slot name="a">` triggers `HTMLSlotElement::AttributeChanged`, which invokes `SlotAssignment::DidRenameSlot`, updating the internal hash map keys and dirtying the assignment state.
*   **Fallback Content:** Fallback content (children of the `<slot>` itself) is never part of the `assigned_nodes_` vector. Blink only renders fallback content during the `FlatTreeTraversal` phase if `slot->AssignedNodes().IsEmpty()` evaluates to `true`.

---
**End of Audit Report.** 
*Awaiting further instructions.*