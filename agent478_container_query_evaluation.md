**AGENT 478 // TECHNICAL AUDIT LOG**
**TARGET:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/css/`)
**SUBJECT:** Container Query Evaluation — Range Satisfaction Mechanics
**STATUS:** ACTIVE

---

### 1. EXECUTIVE SUMMARY
Audit of the Blink CSS engine reveals that Media Queries Level 4/5 range syntax within `@container` rules (e.g., `(400px < width <= 800px)`) is evaluated during the **Interleaved Style/Layout phase**. Range satisfaction is strictly decoupled from DOM tree mutation, relying instead on physical layout dimensions snapped from the LayoutNG formatting context and converted into canonical CSS units before relational evaluation.

---

### 2. ARCHITECTURAL PIPELINE
Container query evaluation is handled primarily by `ContainerQueryEvaluator`, which bridges the gap between the `StyleEngine` and `LayoutNG`. 

The pipeline executes as follows:
1. **Parse Phase:** `MediaQueryParser` (reused for CQ) parses range syntax into an AST represented by `MediaQueryExpNode` subclasses, specifically `MediaQueryFeatureExpNode`.
2. **Bounds Extraction:** A range expression contains a `MediaQueryExpBounds` struct, which holds two `MediaQueryExpComparison` objects: `left` (lower bound) and `right` (upper bound).
3. **Evaluation Trigger:** During `LayoutNG`, when a container's size is determined, `ContainerQueryEvaluator::ContainerChanged()` triggers `MediaQueryEvaluator::Eval()`.

---

### 3. RANGE SATISFACTION MECHANICS

#### 3.1. Canonical Value Resolution
Before a range can be satisfied, both the queried feature (the container's physical state) and the bounds (the author's CSS declarations) must be resolved to canonical units (typically `float` or `LayoutUnit` in `px`).

* **Container Value (`V_actual`):** Extracted via `MediaQueryEvaluator` querying the `MediaValues` object (instantiated as `CSSContainerValues`). If `container-type: inline-size` is active, `V_actual` for `inline-size` is fetched from the physical `LogicalSize` of the `NGPhysicalBoxFragment`.
* **Bound Values (`V_left`, `V_right`):** Computed at evaluation time using `CSSToLengthConversionData`. Relative units (`em`, `rem`, `cqw`, `vh`) and `calc()` expressions are flattened into absolute pixel values based on the container's *own* computed style.

#### 3.2. Relational Evaluation Logic
The core satisfaction check occurs in `MediaQueryEvaluator::Eval(const MediaQueryFeatureExpNode&)`.

A range expression is structured as:
`[V_left] [Op_left] [Feature] [Op_right] [V_right]`

Where `Op` is mapped to the `MediaQueryOperator` enum:
* `kMediaQueryLt` (`<`)
* `kMediaQueryLe` (`<=`)
* `kMediaQueryGt` (`>`)
* `kMediaQueryGe` (`>=`)
* `kMediaQueryEq` (`=`)

**The Satisfaction Algorithm:**
1. **Containment Check:** Verify if the container actually has the required `SizeContainment` axis for the queried feature. (e.g., querying `height` on an `inline-size` container immediately fails and returns `KleeneValue::kUnknown`).
2. **Left Bound Evaluation:** If `bounds.left.IsValid()` is true:
   * Compare `V_left` against `V_actual` using `Op_left`.
   * If false, short-circuit and return `KleeneValue::kFalse`.
3. **Right Bound Evaluation:** If `bounds.right.IsValid()` is true:
   * Compare `V_actual` against `V_right` using `Op_right`.
   * If false, return `KleeneValue::kFalse`.
4. **Result:** If all valid bounds pass, the range is satisfied; return `KleeneValue::kTrue`.

---

### 4. EDGE CASES & PRECISION AUDITS

#### 4.1. Subpixel Layout & `LayoutUnit` Precision
Blink's LayoutNG uses `LayoutUnit` (fixed-point math with 1/64th pixel precision) for layout geometry, while `MediaValues` often resolves CSS lengths into `float` or `double`.
* **Audit Finding:** During comparison in `CompareValue()`, both values are cast to a common type (`double` or `float`). If a container's fractional width is `399.984375px` (a valid `LayoutUnit`), it will **satisfy** `(width < 400px)`. There is no implicit rounding to integer pixels prior to range comparison.

#### 4.2. Three-Valued Logic (Kleene Logic)
Blink implements CSS Conditional Rules using Kleene three-valued logic (`kTrue`, `kFalse`, `kUnknown`). 
* **Range Impact:** If a range contains an invalid or unresolvable unit, or if the container lacks the appropriate `container-type` (e.g., querying `block-size` on an `inline-size` container), the range evaluator yields `kUnknown`.
* **Negation Hazard:** In a query like `@container not (width < 400px)`, if the range evaluates to `kUnknown`, the `not` operator does **not** flip it to `kTrue`. `not(kUnknown)` remains `kUnknown`, which ultimately resolves to falsy when applying styles.

#### 4.3. Zero-Bound and Negative Ranges
Queries such as `(-100px < width < 50px)` are syntactically valid. `V_left` resolves to `-100.0`. Because container physical dimensions are clamped at `0px`, negative lower bounds with `<` or `<=` are trivially satisfied, shifting the burden of satisfaction entirely to the right bound.

---

### 5. AUDIT CONCLUSION
Blink’s range satisfaction implementation for `@container` is robust, deterministic, and strictly adheres to the CSS Conditional Rules Module Level 5 specification. By leveraging the existing `MediaQueryExpBounds` architecture and feeding it dynamic `CSSContainerValues` during the LayoutNG pass, it achieves O(1) evaluation complexity per feature node.

**END OF LOG // AGENT 478 OUT.**