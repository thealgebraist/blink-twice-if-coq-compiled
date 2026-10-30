**AUDIT LOG: AGENT 479**  
**TARGET:** Chromium / Blink Rendering Engine  
**SUBJECT:** `ComputedStyle` Equality (`operator==`) & Equivalence Relation Compliance  
**STATUS:** ACTIVE AUDIT  

---

### 1. Executive Summary
In the Blink rendering engine, `ComputedStyle` represents the resolved CSS declarations applied to a DOM node. The equality operator (`ComputedStyle::operator==`) is the foundational gatekeeper for Style Sharing, Style Invalidation, and Layout Tree reconstruction (determining the `StyleDifference`). 

For Blink's caching and diffing algorithms to remain deterministic and bug-free, `ComputedStyle::operator==` must strictly adhere to the mathematical definition of an **Equivalence Relation**. Any violation results in incorrect rendering, infinite layout loops, or memory bloat.

---

### 2. Equivalence Relation Properties in `ComputedStyle`

To form a valid equivalence relation over the set of all possible `ComputedStyle` instances $S$, the binary relation $\sim$ (implemented as `operator==`) must satisfy three axioms for all $a, b, c \in S$:

#### A. Reflexivity ($a == a$)
Every `ComputedStyle` instance must be equal to itself.

*   **Blink Implementation:** Fast-path pointer comparison at the root of `ComputedStyle` and its internal `DataRef<T>` subgroups. If `&a == &b`, return `true`.
*   **Audit Risk Factor (IEEE 754 `NaN`):** Deep comparisons occur when pointers differ (e.g., after cloning a style for modification, then reverting the change). If any CSS property resolves to a floating-point `NaN` (Not-a-Number), standard C++ float equality (`NaN == NaN`) evaluates to `false`, violating reflexivity.
*   **Mitigation:** Blink must sanitize layout/style floats at parse/compute time so `NaN` never enters `ComputedStyle`, or use bit-level/custom equality helpers for float fields in generated `ComputedStyleBase` code.

#### B. Symmetry ($a == b \iff b == a$)
The order of operands in a `ComputedStyle` comparison must not affect the result.

*   **Blink Implementation:** `operator==` is generated via Python scripts (`make_computed_style_base.py`) from `css_properties.json5`. It delegates equality checks down to sub-structures (`StyleSurroundData`, `StyleBoxData`, `StyleInheritedData`, etc.).
*   **Audit Risk Factor (Polymorphic Sub-objects):** Properties like `CursorList`, `BasicShape`, or `ShadowList` rely on `base::ValuesEquivalent(a, b)` to dereference `scoped_refptr` or `Member` pointers. If a subclass of a style value overrides `operator==` asymmetrically (e.g., comparing a base class to a derived class improperly), symmetry breaks.
*   **Mitigation:** All polymorphic style data types (e.g., `StyleImage`, `BasicShape`) must check exact `GetType()` equality before casting and comparing member variables.

#### C. Transitivity ($a == b \land b == c \implies a == c$)
If Style A equals Style B, and Style B equals Style C, Style A must equal Style C.

*   **Blink Implementation:** Ensure all fields participating in equality are evaluated deterministically without tolerance thresholds.
*   **Audit Risk Factor 1 (Epsilon Float Comparisons):** If a sub-property uses "fuzzy" float matching (e.g., `std::abs(a - b) < epsilon`), transitivity is instantly violated. A could be within $\epsilon$ of B, and B within $\epsilon$ of C, while A and C differ by $2\epsilon$.
*   **Audit Risk Factor 2 (Cache/Lazy Evaluation State):** `ComputedStyle` contains mutable caches (e.g., cached pseudo-element styles, resolved font metrics) that are not semantically part of the CSS cascade. If `operator==` conditionally compares a field only when a "is_cached" flag is set on both objects, transitivity fails.
*   **Mitigation:** 
    1. Exact equality (`==`) must be used for all numeric primitives in `ComputedStyle`. Layout units (`LayoutUnit`) use fixed-point arithmetic, avoiding float drift.
    2. Transient caches and flags (e.g., `MatchedPropertiesCache` status, `IsEnsuredInDisplayNone`) must be explicitly excluded from equality generation via the `custom_compare` or `field_template` flags in `css_properties.json5`.

---

### 3. Blink-Specific Architectural Constraints

In addition to standard algebraic properties, Agent 479 enforces the following engine-specific invariants on `ComputedStyle` equivalence:

#### The Copy-on-Write (`DataRef`) Invariant
`ComputedStyle` heavily utilizes the Flyweight pattern via `DataRef<T>` to group rare and inherited properties. 
*   **Rule:** `DataRef<T>::operator==` checks `data_.get() == other.data_.get() || *data_ == *other.data_`.
*   **Constraint:** If `T::operator==` is not a valid equivalence relation, the behaviour of `ComputedStyle::operator==` will change depending on whether two styles happen to share the same memory pointer or were allocated separately. **Pointer equality must strictly imply value equality.**

#### Equivalence Classes vs. `StyleDifference`
`ComputedStyle::operator==` defines the finest-grained equivalence class (Logical Identity). However, Blink also uses coarser equivalence relations during the lifecycle:
1.  **Visual Equivalence:** `a.VisualInvalidationDiff(document, b)`
2.  **Layout Equivalence:** `a.LayoutInvalidationDiff(document, b)`
*   **Audit Invariant:** Logical equality must be a strict subset of Layout and Visual equivalence. If `a == b` is `true`, `ComputeDifference(a, b)` **must** yield `StyleDifference::kEqual`.

---

### 4. Summary of Audit Directives
To maintain the integrity of Blink's style resolution engine, any patch touching `css_properties.json5`, `ComputedStyle`, or its `Style*Data` sub-structs must guarantee:
1.  **Zero `NaN` propagation** into stored fields (Preserves Reflexivity).
2.  **Strict type-checking** in polymorphic `StyleImage`/`BasicShape` comparisons (Preserves Symmetry).
3.  **Zero epsilon/fuzzy matching** and **complete exclusion of non-semantic/cached flags** in `operator==` (Preserves Transitivity).

*End of Audit Log. Agent 479 standing by.*