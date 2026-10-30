**AGENT 419 // AUDIT REPORT: BLINK CSS ENGINE**  
**SUBSYSTEM:** `StyleCascade` & `CSSVariableResolver`  
**SUBJECT:** Conditional Fallback Substitution in `var()` Evaluation

---

### 1. Executive Summary
In the Chromium/Blink rendering engine, CSS custom property resolution (`var()`) utilizes a lazy, conditionally evaluated fallback mechanism. Under the CSS Custom Properties for Cascading Variables Module Level 1 specification, the fallback component of `var(<custom-property-name>, <declaration-value>?)` must only be substituted if the referenced property is **initial**, **guaranteed-invalid**, or part of a **dependency cycle**. 

Since the deployment of the `StyleCascade` architecture (replacing the legacy `CSSVariableResolver` path), Blink parses `var()` tokens into a flat `CSSVariableData` stream and defers fallback evaluation until the cascade resolution phase (`ResolveSubstitutions`).

---

### 2. Tokenization & AST Representation
Blink does not construct a heavy Abstract Syntax Tree (AST) for custom properties. Instead, during the parse phase (`CSSVariableParser`), declarations containing `var()` are tokenized via `CSSTokenizer` and stored as unparsed token ranges within a `CSSVariableData` object (`is_animation_tainted_`, `needs_variable_resolution_`).

For a rule such as:
```css
color: var(--primary, var(--secondary, #ff0000));
```
Blink verifies syntax validity (matching parentheses, non-empty custom property ident) at parse time, but does **not** validate whether the fallback tokens (`var(--secondary, #ff0000)`) are valid for the target property (`color`).

---

### 3. The `StyleCascade` Resolution Loop
Conditional fallback evaluation occurs in `third_party/blink/renderer/core/css/resolver/style_cascade.cc`. When `StyleCascade::Apply()` runs, it resolves custom properties on the `ComputedStyle` before applying standard properties.

The core evaluation entry point is `StyleCascade::ResolveSubstitutions` which delegates token stream traversal to `StyleCascade::ResolveVarInto`.

#### Step-by-Step Evaluation Logic:
1. **Consume Custom Property Ident:** The `CSSParserTokenRange` consumes the function token `var(` and extracts the argument `<custom-property-name>` (e.g., `--primary`).
2. **State Lookup:** Blink looks up the property in the `CascadeMap`. If the property is in the map, has not been resolved yet, and is currently being Applied, `ResolveCustomProperty` is invoked recursively.
3. **Cycle Detection:** Blink tracks resolution state using a `CycleDetector` (maintaining a stack of currently resolving properties). 
4. **Data Retrieval:** Blink fetches the `CSSVariableData` associated with the custom property from the `ComputedStyle`.

---

### 4. Conditional Branching Mechanics
After attempting to retrieve the `CSSVariableData` for `--primary`, Blink reaches the conditional substitution junction in `StyleCascade::ResolveVarInto`:

#### Condition A: Primary Property is Valid (Short-Circuit)
If the lookup returns a valid, non-null `CSSVariableData` pointer (which is not `guaranteed-invalid`) and no cycle is detected:
* **Action:** Blink appends the tokens of `--primary` to the output token sequence.
* **Fallback Handling:** If a comma token `,` follows `--primary` in the current `CSSParserTokenRange`, **Blink skips the fallback entirely without resolving it.** It fast-forwards the token range pointer to the end of the `var()` block. 
* **Audit Note (Spec Compliance):** Because the fallback is not resolved when the primary succeeds, a cyclical reference or syntax error inside an unused fallback does *not* invalidate the declaration (unless it violates basic tokenization balance rules at parse time).

#### Condition B: Primary Property Triggers Fallback
Fallback evaluation is triggered if and only if one of the following states is met:
1. **Unset/Initial:** The custom property is not defined on the element or inherited from the parent (`data == nullptr`).
2. **Guaranteed-Invalid:** The property was explicitly set to `initial`, or its own internal `var()` resolution failed previously.
3. **Cycle Detected (`in_cycle == true`):** If `--primary` references `--secondary` and `--secondary` references `--primary`, the `CycleDetector` flags both properties. Blink treats the current lookup as invalid.

* **Action:** Blink checks if the next token in the `CSSParserTokenRange` is `kCommaToken`.
    * **If NO comma exists:** `ResolveVarInto` returns `false`. The entire containing property becomes **Invalid at Computed-Value Time (IACVT)**.
    * **If a comma EXISTS:** Blink consumes the comma (and any immediately following whitespace, per spec edits) and passes the remaining `CSSParserTokenRange` (the fallback) recursively into `ResolveTokensInto()`.

---

### 5. Edge Cases & Audit Findings in Blink

#### A. Empty Fallbacks (`var(--foo, )`)
In Blink, if a comma token is present, but the remaining `CSSParserTokenRange` before the closing parenthesis is empty (or consists solely of whitespace), `ResolveTokensInto` succeeds and appends *zero tokens* to the output stream.
* **Result:** Valid substitution of an empty token stream. E.g., `margin: 10px var(--empty, ) 20px;` resolves to `margin: 10px 20px;`.

#### B. Animation-Tainted Fallbacks
Custom properties interpolated inside `@keyframes` are marked `is_animation_tainted_ = true` on their `CSSVariableData`. 
* **Audit Verification:** During conditional fallback substitution, if `--primary` fails and `--fallback` is substituted, the resulting `CSSVariableData` inherits the `is_animation_tainted_` flag from `--fallback`. If the final resolved token stream is animation-tainted and is being substituted into a restricted property ( specifically `animation-name`), Blink intercepts this post-resolution and forces the property to IACVT to prevent animation-triggering-animation loops.

#### C. Invalid at Computed-Value Time (IACVT) Propagation
If the fallback itself is substituted (e.g., `color: var(--missing, not-a-color)`), `ResolveTokensInto` will return `true` because `not-a-color` is a valid token stream. However, once `ResolveSubstitutions` finishes building the composite token stream, it passes the stream to `CSSPropertyParser::ParseSingleValue`.
* When `ParseSingleValue` fails to parse `not-a-color` against the grammar of `color`, Blink drops the declaration and resets the property to its `unset` value (which resolves to `inherited` for `color`, or `initial` for non-inherited properties), completely bypassing any lower-priority declarations in the `CascadeMap`.

#### D. Token Count Limits (DoS Prevention)
Known vulnerability vector: Deeply nested conditional fallbacks (The "Billion Laughs" attack via CSS variables).
* **Blink Mitigation:** Inside `StyleCascade::ResolveTokensInto`, every appended token increments a counter. If the total resolved token size exceeds `CSSVariableData::kMaxSubstitutionBytes` (currently 64KB / 65,536 bytes), substitution immediately aborts, returns `false`, and marks the property IACVT.

---
**END OF AUDIT REPORT // AGENT 419**