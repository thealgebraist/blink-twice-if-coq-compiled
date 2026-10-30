**AGENT 420 // AUDIT LOG: BLINK `@property` REGISTRATION**
**TARGET:** Chromium `third_party/blink/renderer/core/css/`

In Blink, the registration of custom properties (via CSS `@property` or JS `CSS.registerProperty()`) bridges the CSS parser/OM and the computed style engine. Below is the audit detailing how registrations are inserted into the property dictionary and how their initial values are bound and resolved.

---

### 1. Property Dictionary Insertion (`PropertyRegistry`)

Regardless of the entry point, all property registrations converge on the document’s **`PropertyRegistry`** (`core/css/property_registry.cc`), which acts as the local dictionary for custom property definitions.

#### Entry Points:
*   **CSS (`@property`):** Parsed into a `StyleRuleProperty`. During style sheet collection (`RuleSet`), these rules are extracted and routed to the `StyleEngine`.
*   **JS (`CSS.registerProperty`):** Invokes `PropertyRegistration::registerProperty()`, validating the `PropertyDefinition` IDL dictionary.

#### The Insertion Mechanism:
1.  **Object Creation:** A `PropertyRegistration` object is instantiated containing:
    *   `name` (`AtomicString`)
    *   `syntax` (`CSSSyntaxDefinition`)
    *   `inherits` (`bool`)
    *   `initial` (`const CSSValue*`)
    *   `initial_variable_data` (`scoped_refptr<CSSVariableData>`)
2.  **Dictionary Structure:** `PropertyRegistry` maintains a hash map of registrations:
    ```cpp
    HeapHashMap<AtomicString, Member<const PropertyRegistration>> registrations_;
    ```
3.  **Conflict Resolution:** 
    *   **JS Registrations:** Checked via `PropertyRegistry::Registration()`. If the `AtomicString` key already exists, insertion aborts and Blink throws an `InvalidModificationError` DOMException.
    *   **CSS `@property`:** Handled via cascade order during `StyleEngine::UpdateActiveStyle()`. Rules are processed in cascade order; later `@property` rules overwrite earlier ones in the registry (though JS registrations always take precedence over CSS rules).
4.  **Invalidation:** Upon successful insertion into `registrations_`, `StyleEngine::PropertyRegistryChanged()` is triggered. This increments the `PropertyRegistry` version and schedules a full style recalc across the document, as existing `var()` references may now resolve differently.

---

### 2. Initial Value Binding

Binding the `initial-value` is the most security- and performance-critical step of registration. It must be parsed, validated against the `syntax`, and checked for computational independence before it can be bound to a `ComputedStyle`.

#### Step A: Tokenization and Syntax Parsing
1.  If the syntax is **universal (`*`)**, the initial value is tokenized via `CSSTokenizer` and stored directly as a raw token stream inside a `CSSVariableData` object. No `CSSValue` is generated.
2.  If the syntax is **typed** (e.g., `<length>`, `<color>`), the initial value string is passed to `CSSSyntaxDefinition::Parse()`. This invokes the `CSSPropertyParser` to produce a concrete `CSSValue` (e.g., `CSSNumericLiteralValue`, `CSSColor`). If parsing fails, registration aborts (`SyntaxError`).

#### Step B: Computational Independence Verification
Per the CSS Properties and Values API spec, an initial value cannot depend on the style of the element (unless it's a root-relative unit, which is resolved globally). 
*   Blink enforces this via **`CSSPropertyParser::IsComputationallyIndependent(const CSSValue&)`**.
*   **Rejected:** `em`, `ex`, `ch`, `lh`, `%` (if layout-dependent), `var()`, `calc(10px + 2em)`.
*   **Accepted:** `px`, `vw`, `vh`, `deg`, `s`, `rem` (in specific contexts, though generally font-relative units are barred).
*   If this check fails, registration throws a `SyntaxError`.

#### Step C: Style Builder & Resolution Binding
Even if a value is "computationally independent," it might still be a *specified* value that needs conversion to a *computed* value (e.g., converting `10vw` or `2in` into canonical pixels, or resolving `calc(10px + 10px)`).

Blink binds the initial value to the rendering pipeline during `PropertyRegistration::Create`:
1.  **Initial `CSSVariableData` Generation:** The original string is stored as `CSSVariableData` for serialization (`getComputedStyle`).
2.  **Resolution via Initial Style:** Blink creates a temporary or references the document's initial `ComputedStyle` alongside a baseline `CSSToLengthConversionData` (configured with default viewport dimensions and root font sizes).
3.  **`StyleBuilderConverter` Execution:** The parsed `CSSValue` is passed through `StyleBuilderConverter::ConvertRegisteredPropertyInitialValue()`. 
    *   Lengths are flattened to canonical `px`.
    *   Colors are resolved to absolute RGB/ Oklab values.
4.  **Final Binding:** The resulting computed `CSSValue` and `CSSVariableData` are permanently bound to the `PropertyRegistration` instance.

---

### 3. Application to `ComputedStyle`

When an element's style is calculated (`ElementStyleResources` / `StyleResolver`):
1.  `ComputedStyle` holds two groups of custom properties: `InheritedVariables` and `NonInheritedVariables`.
2.  When a custom property is accessed (via `var()` or `CSSComputedStyleDeclaration`), Blink queries `ComputedStyle::GetVariableValue(name)`.
3.  If the element does not explicitly define the property in its cascade, Blink falls back to the `PropertyRegistry`.
4.  It fetches `PropertyRegistration::Initial()` (the pre-computed `CSSValue`) and `PropertyRegistration::InitialVariableData()`, bypassing the need to re-parse or re-compute the initial value for every node in the DOM tree.

**AUDIT CONCLUSION:** Dictionary insertion is strictly guarded by `AtomicString` hashing in `PropertyRegistry`. Initial value binding relies heavily on `StyleBuilderConverter` and `IsComputationallyIndependent()` to ensure that registered initial values are pre-flattened into canonical `CSSValue` singletons, preventing layout-loop vectors during style resolution. 

**// END LOG**