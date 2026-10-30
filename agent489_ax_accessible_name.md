**AUDIT LOG: AGENT 489**
**SUBJECT:** Blink Engine (`AXObject`) Accessible Name Derivation (`accName`)
**SPECIFICATION REFERENCE:** W3C Accessible Name and Description Computation 1.2 (AccName)
**SOURCE TARGET:** `third_party/blink/renderer/modules/accessibility/ax_node_object.cc`

Below is the strict precedence order utilized by the Blink accessibility engine (`AXObject::GetName` / `AXNodeObject::TextAlternative`) to compute the Accessible Name of a DOM node. Evaluation terminates at the first step that returns a non-empty string, unless recursive calculation is triggered.

### **PRECEDENCE ORDER (Highest to Lowest)**

#### **1. Visibility & Exclusion Check (Pre-condition)**
Before derivation begins, if the node is hidden (`display: none`, `visibility: hidden`, `aria-hidden="true"`) AND is **not** currently being referenced by an `aria-labelledby` or `aria-describedby` traversal, computation aborts and returns `""` (Empty).

#### **2. `aria-labelledby` (Highest Priority)**
*   **Mechanism:** Resolves the IDREFs listed in the attribute. 
*   **Behavior:** Initiates a recursive `TextAlternative` walk on the target nodes, concatenating results with spaces.
*   **Blink Constraints:** 
    *   Overrides all other naming mechanisms, including another `aria-labelledby` on the referenced node (prevents infinite loops; recursion depth is strictly 1 level for `labelledby`).
    *   Can traverse into hidden DOM subtrees (`display: none`).

#### **3. `aria-label`**
*   **Mechanism:** Evaluates the literal string value of the `aria-label` attribute on the current node.
*   **Blink Constraints:** If the string is empty or consists only of whitespace, Blink falls through to Step 4.

#### **4. Native Host Language Labelling (HTML-Specific)**
If ARIA attributes do not yield a name, Blink evaluates native HTML associations based on the element's tag/role:
*   **Form Controls (`<input>`, `<select>`, `<textarea>`, etc.):**
    *   **4a. `<label>` association:** Via the `for="[id]"` attribute or by implicit wrapping (`<label><input></label>`).
*   **`<img>` and `<area>`:** The `alt` attribute (Note: `alt=""` sets the role to `presentation`/`none`, effectively halting name computation).
*   **`<input type="image">`:** Checks `alt` attribute, then falls back to `value`.
*   **`<input type="button|submit|reset">`:** The `value` attribute. If absent on `submit` or `reset`, Blink provides localized default strings (e.g., "Submit").
*   **`<fieldset>`:** The text content of the first child `<legend>`.
*   **`<table>`:** The text content of the first child `<caption>`.
*   **`<figure>`:** The text content of the child `<figcaption>`.
*   **`<details>`:** The text content of the child `<summary>`.
*   **SVG Elements:** The text content of the child `<title>` element.

#### **5. Embedded Control Value (Recursive Context Only)**
*   **Mechanism:** If the current calculation is part of a recursive traversal (e.g., inside a `<label>` or `aria-labelledby`), and the node is an embedded control (textbox, combobox, listbox, range), Blink extracts the **current value** of the control to use as part of the outer label.

#### **6. Name From Content (Subtree Text Walk)**
*   **Eligibility:** Only executed if the element's computed ARIA role supports "Name from Content" (e.g., `button`, `link`, `heading`, `checkbox`, `menuitem`, `tab`, `cell`). Roles like `generic` (`div`/`span`), `group`, or `region` skip this step unless they are the target of a `labelledby` traversal.
*   **Mechanism:** Depth-first traversal of all child nodes, concatenating:
    *   **6a. CSS Pseudo-elements:** Content from `::before` and `::after` (including `alt` text defined in CSS `content` properties).
    *   **6b. Text Nodes:** Raw rendered text.
    *   **6c. Child Elements:** Recursively runs steps 1–6 on children (e.g., picking up an `<img alt="foo">` inside a `<button>`).

#### **7. Tooltip / Fallback Attributes (`title` and `placeholder`)**
If all preceding mechanisms fail to produce a non-empty string, Blink falls back to secondary attributes:
*   **7a. `placeholder` / `aria-placeholder`:** Used as a fallback name for text inputs *only* if no label (`<label>`, `aria-label`, `title`) is present. *(Audit Note: Spec places `title` above `placeholder`, though Blink occasionally promotes `placeholder` to `Name` if `title` is absent, otherwise mapping `placeholder` to properties).*
*   **7b. `title` attribute:** The global HTML `title` attribute is used as the final resort for the Accessible Name. (If a name was already found in steps 2–6, `title` is instead mapped to the *Accessible Description*).

---
**END OF AUDIT.** 
*Awaiting further directives, Agent 489.*