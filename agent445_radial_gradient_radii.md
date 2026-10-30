**Audit Report: Blink Rendering Engine — Radial Gradient Radii Non-Negativity & Clamping**
**Auditor:** Agent 445  
**Target:** Chromium / Blink (`third_party/blink/renderer/core/`)  
**Scope:** CSS Radial Gradient Radii Non-Negativity Enforcement

---

### 1. Executive Summary
Per the CSS Images Module Level 3 specification (Section 3.2.1), explicit radii provided in a `radial-gradient()` or `repeating-radial-gradient()` function cannot be negative. Blink enforces this non-negativity across three distinct phases of the rendering pipeline: **Parse-Time Validation**, **Length Calculation (`calc()`) Clamping**, and **Layout/Paint-Time Resolution**.

---

### 2. Phase 1: Parse-Time Validation (Syntax Rejection)
When a CSS stylesheet is parsed, Blink immediately rejects literal negative values for radial gradient radii, invalidating the entire CSS declaration.

* **Location:** `third_party/blink/renderer/core/css/properties/css_parsing_utils.cc`
* **Function:** `ConsumeRadialGradient` / `ConsumeDeprecatedRadialGradient`
* **Mechanism:** 
  When the parser encounters an explicit size (a `<length>` for circles, or `<length-percentage>{2}` for ellipses), it invokes `ConsumeLength` or `ConsumeLengthOrPercent` with the `CSSPrimitiveValue::ValueRange` parameter explicitly set to `kValueRangeNonNegative`.
* **Behavior:**
  * `radial-gradient(50px, red, blue)` $\rightarrow$ **Valid** (`kValueRangeNonNegative` satisfied).
  * `radial-gradient(-50px, red, blue)` $\rightarrow$ **Invalid**. `ConsumeLength` returns `nullptr`, causing `ConsumeRadialGradient` to abort and drop the property.

---

### 3. Phase 2: `calc()` Expressions & Interpolation Clamping
While literal negative values are caught by the parser, CSS `calc()` expressions (e.g., `calc(10px - 50px)` or `calc(50% - 100px)`) cannot always be resolved at parse time, especially if they depend on layout-dependent units (`%`, `vw`, `em`). 

* **Location:** `third_party/blink/renderer/core/css/css_math_expression_node.cc` & `length_functions.cc`
* **Mechanism:** 
  Because the `CSSPrimitiveValue` was constructed under the `kValueRangeNonNegative` constraint during parsing, the resulting `CalculationValue` retains this range restriction flag.
* **Behavior:**
  Instead of dropping the declaration at parse time, the specification dictates that resolved `calc()` values must be **clamped** to the allowed range. When Blink evaluates the math expression into a `Length` object:
  $$\text{Resolved Radius} = \max(0.0f, \text{Evaluated Calc Value})$$
  *Note: This same clamping mechanism applies to CSS Transitions/Animations of gradients where cubic-bezier timing functions might temporarily overshoot into negative territory.*

---

### 4. Phase 3: Layout & Paint-Time Resolution (Skia Boundary)
Before passing the gradient parameters to the Skia graphics library (`SkGradientShader`), Blink resolves the CSS values against the target element's concrete bounding box (`FloatSize`).

* **Location:** `third_party/blink/renderer/core/css/css_gradient_value.cc`
* **Function:** `CSSRadialGradientValue::CreateShader` / `ResolveRadius`
* **Mechanism:**
  1. **Explicit Sizing:** Blink resolves `Length` objects to `float` pixel values using `FloatValueForLength()`. Because the `Length` carries the non-negative constraint from Phase 2, any negative resolution is clamped to `0.0f`.
  2. **Implicit Sizing (Keywords):** For keywords (`closest-side`, `farthest-corner`, etc.), radii are derived using Euclidean distance (`std::hypot`) or absolute deltas (`std::abs`) between the gradient center and the box edges. By mathematical definition, these yield non-negative values ($\ge 0.0f$).
  3. **Defensive Clamping:** As a final safeguard against floating-point inaccuracies (such as negative zero `-0.0f` or sub-epsilon underflows), Blink ensures radii are strictly $\ge 0.0f$ before constructing the `Gradient::CreateRadial` object.

---

### 5. Handling of Zero-Radius Edge Cases (Degenerate Gradients)
When a negative `calc()` radius is clamped to `0`, the gradient becomes **degenerate**. Blink handles a `0px` radius as follows:

* **Circle (`r = 0`):** The gradient renders as a solid color matching the *last* color-stop in the stop list, as the entire paint area is considered "outside" the $0$-radius circle.
* **Ellipse (`rx = 0` or `ry = 0`):** If one axis is clamped to `0` while the other is positive, the ellipse collapses into a line. Per CSS spec and Blink's implementation in `Gradient::CreateRadial`, to avoid division-by-zero in elliptical scaling transformation matrices, a zero-radius axis is treated identically to a degenerate 0-radius circle (or scaled via an epsilon fallback depending on the Skia backend), painting the last stop color everywhere.

### 6. Audit Conclusion
**Status: COMPLIANT.**  
Blink strictly adheres to the W3C specification regarding radial gradient radii non-negativity. Literal negatives are blocked at the parser gate (`kValueRangeNonNegative`), dynamic negatives (`calc()`) are clamped to `0.0f` at evaluation, and Skia shaders are protected from negative radii allocations.