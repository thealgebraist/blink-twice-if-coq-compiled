**AUDIT REPORT: AGENT 485**
**SUBJECT:** Blink Engine Radio Group Mutual Exclusion & Uniqueness
**COMPONENT:** `blink/renderer/core/html/forms/radio_input_type.cc`, `radio_button_group_scope.cc`

### 1. Executive Summary
In the Chromium Blink rendering engine, the mutual exclusion of `<input type="radio">` elements is governed by the `RadioButtonGroupScope` class. A radio group guarantees that **at most one** radio button within a defined uniqueness boundary can hold the `checked` state at any given lifecycle phase. 

Below is the technical breakdown of how Blink defines group uniqueness, enforces mutual exclusion, and handles DOM edge cases.

---

### 2. Uniqueness Boundaries (Scoping Criteria)
For two or more radio buttons to be subject to mutual exclusion, Blink requires them to share a specific uniqueness signature. A radio button is added to a `RadioButtonGroup` if and only if it matches the following four criteria:

1. **TreeScope Isolation (Shadow DOM Boundary):**
   Radio groups do not bleed across Shadow DOM boundaries. Uniqueness is strictly bound to the `TreeScope` (either the `Document` or a specific `ShadowRoot`). Each `TreeScope` maintains its own `RadioButtonGroupScope` instance.
2. **Form Owner Association:**
   Uniqueness is partitioned by the `<form>` owner. 
   * Radios associated with the same `<form>` (either via DOM hierarchy or the `form="id"` attribute) share a scope.
   * Radios with *no* form owner share a default document-level (or shadow-root-level) scope within their `TreeScope`.
3. **Name Attribute Normalization:**
   The `name` attribute defines the group identifier within the `TreeScope` and `Form` boundary. 
   * **Case Sensitivity:** Blink enforces **case-sensitive** matching (via `AtomicString` comparison) for radio group names, aligning with the current WHATWG HTML specification.
   * **Empty Names:** An `<input type="radio">` without a `name` attribute, or with `name=""`, is treated as an orphan. It is excluded from `RadioButtonGroupScope` tracking and cannot mutually exclude other nameless radios.
4. **Input Type:**
   The element must strictly resolve to `input[type="radio"]`. Dynamic mutation of the `type` attribute triggers immediate removal from or addition to the `RadioButtonGroupScope`.

---

### 3. Mutual Exclusion Enforcement Mechanisms
Blink maintains a pointer to the `checked_button_` inside the `RadioButtonGroup` C++ object. This ensures $O(1)$ lookup for the currently active element and prevents race conditions.

#### A. User Interaction vs. Programmatic Mutation
* **User Interaction:** When a user clicks or uses arrow keys to select a radio button, Blink sets its `checked` state to `true`, locates the `checked_button_` via `RadioButtonGroupScope`, sets that previous button's `checked` state to `false`, and queues `input` and `change` events.
* **Programmatic (`element.checked = true`):** Immediate mutual exclusion occurs synchronously. The dirtyness flag of the radio button is set to `true`, the previous `checked_button_` is unchecked, and the internal pointer is updated. No `change` events are fired.

#### B. The "Last-In-Wins" Resolution (DOM Mutations & Parsing)
A critical aspect of Blink's uniqueness audit is how it handles state conflicts when multiple radio buttons claim the `checked` state simultaneously (e.g., during initial HTML parsing or `appendChild` operations):
* **Rule:** The **last** radio button inserted into the group with a `checked` state takes precedence.
* **Execution:** If Radio A is currently `checked`, and Radio B (having the `checked` attribute and matching scope/name) is inserted into the DOM, `RadioButtonGroup::Add()` detects that Radio B is checked. It synchronously unchecks Radio A and updates `checked_button_` to point to Radio B.
* **Historical Note:** Even if Radio A had its `checked` state dirtied by the user, inserting a new pre-checked Radio B into the DOM will override Radio A.

#### C. Attribute Mutations
If an element's `name`, `type`, or `form` attribute is mutated via JS:
1. Blink calls `RadioButtonGroupScope::RemoveButton()` using the old state.
2. If the removed button was the `checked_button_`, the group's `checked_button_` pointer becomes `nullptr` (leaving the group with zero checked items).
3. Blink calls `RadioButtonGroupScope::AddButton()` with the new state.
4. If the mutated button is currently `checked`, it immediately overrides and unchecks any existing `checked_button_` in the target group.

---

### 4. Auxiliary Uniqueness: The `required` Attribute
Blink's `RadioButtonGroup` also tracks constraint validation uniqueness. 
* A radio group is considered "required" if **at least one** non-disabled radio button in the group possesses the `required` attribute.
* Because of mutual exclusion, if *any* radio button in the group is `checked`, the validity state `valueMissing` evaluates to `false` for **all** radio buttons in that group.

### 5. Audit Conclusion
Blink's implementation of radio group mutual exclusion is strictly deterministic. By tying `RadioButtonGroupScope` to the `TreeScope` and indexing by `(HTMLFormElement*, AtomicString name)`, Blink prevents cross-component leakage in Web Components while maintaining $O(1)$ state resolution for mutual exclusion. 

**End of Report.**