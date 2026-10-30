**AUDIT REPORT: BLINK CSS CUSTOM PROPERTY RESOLUTION & CASCADE INHERITANCE**
**Agent ID:** 417
**Target Subsystem:** `third_party/blink/renderer/core/css/`
**Subject:** Custom Property (`--*`) Lifecycle, Substitution, and Inheritance Mechanics

---

### 1. Executive Summary
In the Blink rendering engine, CSS Custom Properties (CSS Variables) are treated as first-class citizens within the cascade, yet their resolution pipeline diverges significantly from standard CSS properties. Unlike standard properties, which are parsed into strongly-typed `CSSValue` representations and resolved into fixed offsets within `ComputedStyle` bitfields, custom properties are retained largely as tokenized streams (`CSSVariableData`) until substitution is required via `var()`. By default, all untyped custom properties inherit. Registered custom properties (via `@property` or `CSS.registerProperty`) introduce type-checking and configurable inheritance flags, splitting the storage and resolution paths into two distinct classifications: **Inherited** and **Non-Inherited** variables.

---

### 2. Data Structures & Storage Architecture

#### 2.1 `ComputedStyle` Storage
Because custom property names are unbounded and defined at runtime, they cannot be statically mapped to struct members in `ComputedStyle`. Blink utilizes a dual-storage architecture within `StyleInheritedData` and `StyleNonInheritedData`:

*   **`StyleInheritedVariables`**: Houses all standard (unregistered) custom properties and registered custom properties defined with `inherits: true`. Uses a Copy-on-Write (CoW) `DataRef` pattern.
*   **`StyleNonInheritedVariables`**: Houses registered custom properties explicitly defined with `inherits: false`.

Inside these containers, properties are divided into two maps keyed by `AtomicString` (the `--*` identifier):
1.  **`Data` Map (`HashMap<AtomicString, scoped_refptr<CSSVariableData>>`)**: Stores the raw or resolved token stream.
2.  **`Values` Map (`HashMap<AtomicString, Member<const CSSValue>>`)**: Used exclusively for registered custom properties. Stores the parsed, strongly-typed `CSSValue` equivalent of the token stream.

#### 2.2 `CSSVariableData` & `CSSUnparsedDeclarationValue`
When the CSS parser encounters `--foo: bar`, it does not validate `bar` against a specific grammar (beyond basic CSS tokenization rules and matching brackets/quotes). 
*   It constructs a `CSSUnparsedDeclarationValue` containing a `CSSVariableData` payload.
*   `CSSVariableData` holds the serialized string representation alongside metadata flags: `is_animation_tainted_`, `needs_variable_resolution_` (true if the stream contains `var()` or `env()`), and font-unit dependency flags (`has_font_units_`, `has_root_font_units_`).

---

### 3. The Cascade and Inheritance Phase

During `StyleResolver::ResolveStyle`, custom properties are processed before standard properties because standard properties may depend on them via `var()`.

#### 3.1 Initial Inheritance (Fast-Path)
Before applying the current element's matched declarations:
1.  `StyleResolverState` initializes the element's `ComputedStyleBuilder` using the parent element's `ComputedStyle`.
2.  The `DataRef<StyleInheritedVariables>` pointer is copied directly from the parent to the child. **No deep copying of variable maps occurs if the child does not declare or override custom properties.**
3.  `StyleNonInheritedVariables` is initialized as `nullptr` (or reset to initial values as defined by the `PropertyRegistry`).

#### 3.2 Cascade Population (`StyleCascade`)
Blink’s `StyleCascade` class manages the cascade order and resolution of dependencies:
1.  Matched rules are added to the `CascadeMap`. Custom properties are identified via `CSSPropertyName` and assigned a `CascadePriority`.
2.  `StyleCascade::Apply()` iterates through priorities. Custom properties are resolved during a specific pass before standard properties that have `var()` references.
3.  If a child overrides an inherited custom property, `ComputedStyleBuilder` triggers a Copy-on-Write operation on `StyleInheritedVariables`, mutating the local hash map for the current element.

---

### 4. Custom Property Resolution (`StyleCascade::Resolve`)

Resolving a custom property involves transforming a raw `CSSUnparsedDeclarationValue` (which may contain nested `var()` calls) into a finalized `CSSVariableData` (and a `CSSValue` if registered) stored on `ComputedStyle`.

#### 4.1 Dependency Graph & Cycle Detection (`CascadeResolver`)
Because custom properties can reference one another (`--a: var(--b); --b: var(--a);`), Blink must resolve them recursively using a depth-first search (DFS) managed by `CascadeResolver`.

1.  **Stack Tracking**: When `StyleCascade` attempts to resolve `--a`, it pushes `--a` onto the `CascadeResolver::stack_`.
2.  **Token Substitution**: Blink parses the token stream of `--a`. Upon encountering `var(--b)`, it pauses resolution of `--a` and invokes `ResolveCustomProperty` for `--b`.
3.  **Cycle Detection**: If `--b` attempts to resolve `--a` (which is already in `CascadeResolver::stack_`), a cycle is detected.
    *   `CascadeResolver` marks the cycle pointers.
    *   All properties caught within the dependency loop are immediately flagged as **Invalid at Computed-Value Time (IACVT)**.
4.  **Fallback Execution**: If `--b` is not in a cycle, its resolved token stream is spliced directly into `--a`'s token stream. If `--b` is undefined or IACVT, and `var(--b, <fallback>)` specifies a fallback, the resolver recursively evaluates and splices the fallback stream.

*Audit Note (Resource Exhaustion):* During token splicing, Blink enforces a hard size limit (`CSSVariableData::kMaxSubstitutionBytes`, set to 64KB). If variable expansion exceeds this threshold (e.g., via exponential "billion laughs" style variable nesting), substitution aborts and the property becomes IACVT.

#### 4.2 Invalid at Computed-Value Time (IACVT)
When a custom property fails resolution (due to cyclic dependencies, missing targets without fallbacks, or type mismatches in registered properties), it resolves to the **guaranteed-invalid value**.
*   In Blink, this is represented by setting the property's value in the `ComputedStyle` variable map to `nullptr` (or unsetting it depending on registration status).
*   According to CSS specifications, IACVT behaves identically to `unset`:
    *   If the custom property is **inherited** (all unregistered, or registered with `inherits: true`), it falls back to the parent's computed value (or remains guaranteed-invalid if the parent has none). *Correction*: If a cycle occurs, the property itself does not inherit the parent's value; it becomes guaranteed-invalid (initial value) to break the cycle.
    *   If a standard property (e.g., `color: var(--invalid)`) references an IACVT custom property, the standard property behaves as `unset` (inheriting `color` from parent, or resetting to `initial` if non-inherited like `border`).

---

### 5. Registered Custom Properties (`@property`)

When a property is registered in the `PropertyRegistry`, it bypasses pure-token storage and undergoes strict validation in `CustomProperty::ApplyValue`:

1.  **Token Resolution**: Any `var()` references inside the registered property are resolved into a flattened token stream first.
2.  **Syntax Parsing**: The flattened stream is parsed against the registered `CSSSyntaxDefinition` (e.g., `<length>`, `<color>`).
3.  **Computation (`StyleBuilderConverter`)**:
    *   If parsing fails, the property is marked IACVT (reverting to its inherited value or registered `initial-value`).
    *   If parsing succeeds, relative units are resolved against the current element's context. For example, a registered `<length>` with value `2em` is converted into an absolute pixel `CSSNumericLiteralValue` using the current element's computed `font-size`.
4.  **Dual Storage**: Blink stores both the resolved `CSSValue` (for fast interpolation during animations/transitions) and a newly serialized `CSSVariableData` (representing the computed value, e.g., `"32px"`, so that child elements substituting this variable via `var()` receive the computed pixel value, not `"2em"`).

*Audit Note (Font-Size Dependency):* Because registered `<length>` custom properties depend on `font-size` and `line-height`, `StyleCascade` explicitly resolves `font-size` and `line-height` **prior** to resolving the custom property cascade map. If `font-size` itself uses a custom property, `CascadeResolver` resolves that specific custom property on-demand via the DFS mechanism.

---

### 6. Animation Tainting (Security Boundary)

Per the CSS Variables specification, custom properties can be animated via `@keyframes`. However, to prevent side-channel timing attacks or cross-origin data leaks via `url()` construction, Blink enforces **Animation Tainting**:
*   When `CSSAnimations` interpolates a custom property, the resulting `CSSVariableData` is instantiated with `is_animation_tainted_ = true`.
*   This boolean flag is **infectious**: if `--b` references a tainted `--a` via `var(--a)`, the resolved `CSSVariableData` for `--b` inherits the `is_animation_tainted_` flag.
*   If a standard property that accepts URLs (e.g., `background-image`) substitutes a tainted `CSSVariableData`, `StyleCascade` blocks the substitution and renders the declaration IACVT.

---

### 7. Summary of Inheritance Pipeline

| Property Type | Storage Location | Inheritance Mechanism | Value Inherited by Child | On Failure (IACVT) |
| :--- | :--- | :--- | :--- | :--- |
| **Unregistered (`--*`)** | `StyleInheritedVariables` | CoW Pointer Copy (`DataRef`) | Raw/Substituted Token Stream (`2em` stays `2em`) | Becomes Guaranteed-Invalid (`nullptr`) |
| **Registered (`inherits: true`)** | `StyleInheritedVariables` | CoW Pointer Copy (`DataRef`) | Computed `CSSValue` + Re-serialized Token Stream (`2em` becomes `32px`) | Reverts to Parent Value (or `initial-value` if cycle) |
| **Registered (`inherits: false`)** | `StyleNonInheritedVariables` | Reset per Element | None (Initialized to `PropertyRegistration::Initial()`) | Reverts to Registered `initial-value` |

**End of Report.**