**AUDIT LOG: AGENT 421**  
**TARGET:** Chromium / Blink Engine (`third_party/blink/renderer/core/css/cssom/`)  
**SUBJECT:** CSS Typed OM (`CSSNumericValue`) — Unit Dimension Addition Mechanics  
**STATUS:** ACTIVE AUDIT  

---

### 1. ARCHITECTURAL OVERVIEW
In Blink’s implementation of the CSS Typed OM Level 1 specification, `CSSNumericValue` is the abstract base class for all numeric CSS values. It branches into two primary subclasses:
1. **`CSSUnitValue`**: Represents a single scalar value paired with a specific `CSSPrimitiveValue::UnitType` (e.g., `10px`, `50%`, `2s`).
2. **`CSSMathValue`**: An abstract class representing complex mathematical expressions trees (specifically `CSSMathSum`, `CSSMathProduct`, `CSSMathNegate`, `CSSMathInvert`, `CSSMathMin`, `CSSMathMax`, `CSSMathClamp`).

Addition (`CSSNumericValue::add`) is exposed via V8 bindings and internally routed through `CSSNumericValue::Add()`.

---

### 2. DIMENSIONALITY & TYPE CHECKING (`CSSNumericValueType`)
Before any arithmetic occurs, Blink validates dimensional compatibility using `CSSNumericValueType` (representing the spec's *numeric type*). 

A numeric type is a map of **Base Types** to their integer exponents (powers), plus a **Percent Hint**:
* **Base Types:** `kLength`, `kAngle`, `kTime`, `kFrequency`, `kResolution`, `kFlex`, `kPercent`.

#### The Addition Type-Checking Algorithm (`CSSNumericValueType::Add`)
When adding `Value A` and `Value B`, Blink executes `CSSNumericValueType::Add(type_a, type_b, error_status)`:
1. **Percent Hint Resolution:** If both types have a `PercentHint` and they do not match, addition fails (`DOMException: TypeError`). If one has a hint, it is applied to the other.
2. **Base Type Exponent Matching:** After applying hints, the exponents of all non-zero base types must be identical between `type_a` and `type_b`.
   * *Valid:* `px` (`kLength: 1`) + `em` (`kLength: 1`) -> Matches.
   * *Valid:* `px` (`kLength: 1`) + `%` (`kPercent: 1`) -> Valid *only* inside a `CSSMathSum` node because in CSS, percentages are context-dependent and may resolve to lengths at layout time. The resulting type inherits the base types and sets a `PercentHint` if applicable.
   * *Invalid:* `px` (`kLength: 1`) + `deg` (`kAngle: 1`) -> Mismatch. Throws `TypeError` via `ExceptionState`.

---

### 3. THE ADDITION PIPELINE
When `a.add(b)` is invoked in JS, Blink converts inputs into an internal intermediate representation (`CSSNumericSumValue`) to attempt algebraic simplification before instantiating new Blink Garbage Collected (`GarbageCollected<CSSNumericValue>`) objects.

#### Step 1: Coercion & Flattening
All arguments passed to `add()` are coerced via `CSSNumberishToNumericValue`. Blink attempts to flatten the expression tree.

#### Step 2: Canonical Unit Conversion (`CSSUnitValue` + `CSSUnitValue`)
If both `this` and the operand are `CSSUnitValue` instances:
1. **Identical Units:** If `unit_a == unit_b` (e.g., `10px + 20px` or `5em + 2em`), Blink performs a fast-path scalar addition: `CSSUnitValue::Create(a->value() + b->value(), a->GetInternalUnit())`.
2. **Compatible Canonical Units:** Every absolute dimension has a canonical unit in Blink:
   * `kLength` $\rightarrow$ `px`
   * `kAngle` $\rightarrow$ `deg`
   * `kTime` $\rightarrow$ `s`
   * `kFrequency` $\rightarrow$ `Hz`
   * `kResolution` $\rightarrow$ `dppx`
   
   If `unit_a` and `unit_b` belong to the same base dimension and are **both convertible** (i.e., neither is a font-relative or viewport-relative unit like `em`, `rem`, `vw`), Blink converts `b` to `a`’s unit, or both to the canonical unit.
   * *Audit Note:* Per the CSS Typed OM spec, `CSSUnitValue::SumValue()` converts compatible absolute units to the **canonical unit**. For example, `CSS.in(1).add(CSS.cm(2.54))` converts both to `px` using Blink's fixed conversion ratios (`1in = 96px`, `1cm = 96/2.54 px`) and returns `CSSUnitValue(192, "px")`.

3. **Incompatible Relative Units:** If units share a dimension but cannot be resolved at parse/OM-time (e.g., `10px + 2em` or `50vw + 20%`), fast-path scalar addition aborts. Execution falls through to expression tree construction.

#### Step 3: `CSSNumericSumValue` Map Reduction
For complex expressions (or relative unit mismatches), Blink utilizes `CSSNumericSumValue`.
* A `CSSNumericSumValue` is a list of **Terms**.
* Each **Term** consists of a scalar `double value` and a `UnitMap` (a hash map of `UnitType` $\rightarrow$ `int exponent`).
* **Example:** `10px + 5em + 2in`
  1. `10px` $\rightarrow$ `Term(10, {px: 1})`
  2. `5em` $\rightarrow$ `Term(5, {em: 1})` (Cannot convert to canonical `px` without style/layout context).
  3. `2in` $\rightarrow$ Converted to canonical `px` $\rightarrow$ `Term(192, {px: 1})`.

Blink iterates over the terms, grouping them by identical `UnitMap` keys:
* `{px: 1}` terms are summed: $10 + 192 = 202$.
* `{em: 1}` remains $5$.

#### Step 4: Re-materialization
Blink inspects the reduced `CSSNumericSumValue`:
* **Single Term, Single Unit (Exponent 1):** If the reduction yields a single term with a single unit raised to the power of 1 (e.g., `{px: 1}`), Blink unboxes it and returns a `CSSUnitValue` (`202px`).
* **Single Term, Empty UnitMap:** Returns a `CSSUnitValue` of type `kNumber`.
* **Multiple Terms or Higher-Order Dimensions:** If multiple terms remain (e.g., `202px` and `5em`), or if a unit has an exponent $\neq 1$ (e.g., `px^2` from a prior multiplication), Blink instantiates and returns a `CSSMathSum` object containing a `CSSNumericArray` of the reduced operands.

---

### 4. EDGE CASES & AUDIT FINDINGS IN BLINK

1. **NaN and Infinity Clamping:**
   During scalar addition within `CSSUnitValue` or `CSSNumericSumValue`, IEEE 754 floating-point rules apply. While CSS Values and Units Level 4 allows `calc(NaN)` and `calc(infinity)` during intermediate calculations, Typed OM `CSSUnitValue::Create` explicitly checks `std::isnan()` and `std::isinf()` and will throw a `TypeError` if raw non-finite values are directly instantiated via factory methods, though arithmetic overflow inside `CSSMathSum` may persist until layout-time clamping.

2. **Negation Unwrapping (`sub` as `add`):**
   `CSSNumericValue::sub()` is implemented by negating the right-hand operand (`CSSMathNegate` or multiplying `CSSUnitValue` by `-1`) and passing it directly into the `Add()` pipeline.

3. **UnitMap Sorting (`CSSMathSum` Serialization):**
   When materializing a `CSSMathSum`, Blink must sort the terms alphabetically by their unit strings (with numbers first, percentages second, and alphabetical dimensions thereafter) to comply with the spec’s serialization rules for `CSSMathSum`.

**END OF AUDIT REPORT — AGENT 421**