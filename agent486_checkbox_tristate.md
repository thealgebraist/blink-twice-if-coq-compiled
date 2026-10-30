**AUDIT REPORT: Blink Engine (`HTMLInputElement` - `type="checkbox"`)**
**AUDITOR:** Agent 486
**SUBJECT:** Tri-state (Indeterminate) State Machine and Transition Logic

---

### 1. Architecture Overview
In Blink, a checkbox is not a true tri-state input in terms of form submission; it is a binary state machine (`checked`: true/false) masked by a visual presentation flag (`indeterminate`: true/false). 

The state is governed by two independent boolean properties on the `HTMLInputElement` interface:
1.  **`checked`**: Represents the actual data state. Controlled via HTML attribute `checked` (default state) or IDL property `.checked` (current state).
2.  **`indeterminate`**: Represents the visual masking state. Controlled **exclusively** via the JavaScript IDL property `.indeterminate`.

This creates a 4-state internal matrix, mapped to 3 visual states (`:indeterminate` overrides `:checked` in the UA stylesheet and accessibility tree).

### 2. Internal State Matrix

| State ID | `.indeterminate` | `.checked` | Visual Rendering | CSS Pseudo-classes Matched | Form Submission Value | A11y (`aria-checked`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **S0** | `false` | `false` | Unchecked `[ ]` | `:not(:checked)` | *None (Omitted)* | `"false"` |
| **S1** | `false` | `true` | Checked `[✓]` | `:checked` | `value` (default `"on"`) | `"true"` |
| **S2** | `true` | `false` | Mixed `[-]` | `:indeterminate` | *None (Omitted)* | `"mixed"` |
| **S3** | `true` | `true` | Mixed `[-]` | `:indeterminate`, `:checked` | `value` (default `"on"`) | `"mixed"` |

*Audit Note: In state **S3**, the element matches both `:indeterminate` and `:checked` selectors simultaneously, though the visual rendering is strictly indeterminate.*

---

### 3. State Transitions

#### A. User Interaction (Pointer Click / Keyboard Space)
When a user activates the checkbox, Blink executes a pre-activation step, fires events, and potentially executes a post-activation rollback if the event is canceled.

**Forward Transition (Event not canceled):**
Regardless of the starting state, user activation **always** forces `.indeterminate = false` and inverts `.checked`.

*   **From S0** (`indet: false`, `chk: false`) $\rightarrow$ **To S1** (`indet: false`, `chk: true`)
*   **From S1** (`indet: false`, `chk: true`) $\rightarrow$ **To S0** (`indet: false`, `chk: false`)
*   **From S2** (`indet: true`, `chk: false`) $\rightarrow$ **To S1** (`indet: false`, `chk: true`)
*   **From S3** (`indet: true`, `chk: true`) $\rightarrow$ **To S0** (`indet: false`, `chk: false`)

*Critical Finding:* Transitioning out of the visual "Mixed" state via user click yields **different** results depending on the underlying hidden `.checked` state (S2 goes to Checked; S3 goes to Unchecked).

**Blink Event Lifecycle & Rollback Transition (`event.preventDefault()`):**
In Blink (`CheckboxInputType::WillDispatchClick`), the state is mutated *before* the `click` event is dispatched to the DOM. 

1.  **Pre-Dispatch:** Blink caches `old_checked` and `old_indeterminate`.
2.  **Mutation:** `.checked` is toggled; `.indeterminate` is set to `false`.
3.  **Dispatch:** The `click` event fires. (Inside the `onclick` handler, the DOM reflects the *new* state).
4.  **Evaluation:** 
    *   If `preventDefault()` was **not** called: Blink dispatches the `input` event, followed by the `change` event. Transition is committed.
    *   If `preventDefault()` **was** called: Blink executes `RestoreLegacyPreActivationBehavior`. Both `.checked` and `.indeterminate` are reverted to `old_checked` and `old_indeterminate`. `input` and `change` events are suppressed.

#### B. Programmatic Mutation (JavaScript IDL)
Mutating properties via JS does not trigger `input` or `change` events, and the two properties are strictly orthogonal.

*   **Setting `element.checked = bool`:**
    *   Transitions between **S0 $\leftrightarrow$ S1** OR **S2 $\leftrightarrow$ S3**.
    *   **Does NOT** alter the `.indeterminate` state. Setting `.checked = true` on an S2 element moves it to S3 (visually remains `[-]`).
*   **Setting `element.indeterminate = bool`:**
    *   Transitions between **S0 $\leftrightarrow$ S2** OR **S1 $\leftrightarrow$ S3**.
    *   **Does NOT** alter the `.checked` state.

#### C. Form Reset (`HTMLFormElement.reset()`)
When the parent form is reset, Blink invokes `CheckboxInputType::ResetImpl()`.

*   `.indeterminate` is unconditionally set to `false`.
*   `.checked` is set to the boolean presence of the HTML `checked` content attribute (`defaultChecked`).
*   **Transitions:**
    *   If `<input type="checkbox">` (no attribute): **S0, S1, S2, S3 $\rightarrow$ S0**.
    *   If `<input type="checkbox" checked>`: **S0, S1, S2, S3 $\rightarrow$ S1**.

---

### 4. Blink Engine Edge Cases & Anomalies

1.  **Content Attribute Desynchronization (`setAttribute('checked', ...)`):**
    *   In Blink, every `HTMLInputElement` maintains a `dirty_checkedness_` flag (initially `false`).
    *   While `dirty_checkedness_ == false`, adding/removing the `checked` HTML attribute transitions the state (**S0 $\leftrightarrow$ S1** or **S2 $\leftrightarrow$ S3**).
    *   Once the user clicks the checkbox, or JS sets `.checked`, `dirty_checkedness_` becomes `true`. From that point on, mutating the HTML attribute via `setAttribute` **no longer causes a state transition** (until a Form Reset occurs, which clears the dirty flag).
2.  **State Restoration (Back/Forward Cache):**
    *   Blink's `SaveFormControlState` only serializes the `.checked` boolean.
    *   If a user navigates away from a page with checkboxes in **S2** or **S3** and navigates back, Blink restores them as **S0** or **S1** respectively. The `.indeterminate` state is lost across page loads.
3.  **DOM Cloning (`cloneNode()`):**
    *   `HTMLInputElement::CopyNonAttributePropertiesFromElement` explicitly copies the `indeterminate_` flag, the `checked_` flag, and the `dirty_checkedness_` flag. All states (**S0–S3**) are preserved intact during a `cloneNode()` operation.

**END OF REPORT**