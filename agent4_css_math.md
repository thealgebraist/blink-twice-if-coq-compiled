# Agent 4 Audit Report: Chromium Blink CSS Math Expressions vs. W3C CSS Values and Units Level 4 (Section 10)

This audit provides an architectural, semantic, and formal analysis of Chromium’s Blink CSS Math Expression engine (`third_party/blink/renderer/core/css/css_math_expression_node.h/cc` and `calculation_expression_node.h/cc`) against the W3C CSS Values and Units Module Level 4 specification (Section 10: Mathematical Expressions).

---

## 1. Core AST Data Structures in Blink CSS Math

Blink splits its mathematical expression representation across two distinct phases of the rendering pipeline:
1. **CSS Parsing & Style Resolution AST (`CSSMathExpressionNode`)**: Oilpan-allocated (`GarbageCollected`), preserving syntactic fidelity and unresolved units (`em`, `vh`, `%`) for serialization (`cssText`) and CSSOM inspection.
2. **Computed Style & Layout AST (`CalculationExpressionNode`)**: Thread-safe, `RefCounted` representations embedded within `blink::Length` (via `CalculationValue`) for consumption by LayoutNG.

```
                      +--------------------------+
                      |  CSSMathExpressionNode   |
                      |  (Oilpan GarbageCollected)|
                      +--------------------------+
                                   ^
         +-------------------------+-------------------------+
         |                         |                         |
+--------+----------------+ +------+------------------+ +----+--------------------+
|CSSMathExpressionNumeric | |CSSMathExpressionOperation| |CSSMathExpressionAnchor  |
|Literal                  | |(Add, Mul, Min, Clamp...) | |Query (anchor, size)     |
+-------------------------+ +-------------------------+ +-------------------------+
         |                               |                         |
         +-------------------------------+-------------------------+
                                         | ToCalculationExpression(CSSLengthResolver)
                                         v
                      +--------------------------+
                      |CalculationExpressionNode |
                      |  (WTF::RefCounted)       |
                      +--------------------------+
```

### 1.1. `CSSMathExpressionNode` (Base Class)
* **Location**: `third_party/blink/renderer/core/css/css_math_expression_node.h`
* **State**:
  * `CalculationResultCategory category_`: Tracks the resolved dimensional type of the sub-expression.
  * `bool is_nested_calc_`: Tracks whether the node originated from a nested `calc(...)` for serialization rules.
  * `bool has_comparisons_`, `bool has_anchor_functions_`: Fast-path flags for style invalidation and layout dependencies.
* **Core Virtual Interface**:
  * ` std::optional<double> ComputeValueInCanonicalUnit() const`: Evaluates pure compile-time constants.
  * `double ComputeDouble(const CSSLengthResolver&) const`: Evaluates the AST to an IEEE 754 `double` during style resolution.
  * `scoped_refptr<const CalculationExpressionNode> ToCalculationExpression(const CSSLengthResolver&) const`: Lowering pass to Layout AST when percentages or anchor queries prevent full resolution to a scalar.

### 1.2. `CSSMathExpressionNumericLiteral`
* **State**: Wraps a `Member<const CSSNumericLiteralValue> value_`.
* **Semantics**: Terminal leaf node representing a parsed number paired with a `CSSPrimitiveValue::UnitType` (e.g., `kPixels`, `kPercentage`, `kDegrees`, `kNumber`, or `kUnknown` for math constants like `e`, `pi`, `infinity`, `-infinity`, `NaN`).

### 1.3. `CSSMathExpressionOperation`
* **State**:
  * `Operands operands_` (`HeapVector<Member<const CSSMathExpressionNode>>`): N-ary vector of child nodes. Binary ops have arity 2; `clamp()` has arity 3; `min()` and `max()` have arity $N \ge 1$; stepped-value functions have arity 2.
  * `CSSMathOperator operator_`: Enum identifying the mathematical operation.
* **Representation of Negation & Inversion**:
  * Blink **does not** maintain a dedicated `CSSMathExpressionNegation` or `Invert` AST subclass at the `CSSMathExpressionNode` level. Instead, during parsing or simplification (`CreateArithmeticOperation`), unary negation $-X$ is represented either by multiplying by $-1$ (`kMultiply`), subtracting from $0$ (`0 - X`), or folding the sign directly into a `CSSMathExpressionNumericLiteral`.

### 1.4. `CSSMathExpressionAnchorQuery`
* **State**:
  * `CSSAnchorQueryType type_`: `kAnchor` or `kAnchorSize`.
  * `Member<const CSSValue> anchor_specifier_`: `implicit`, `default`, or a `<dashed-ident>`.
  * `Member<const CSSValue> value_`: The anchor side (`top`, `left`, `center`, `%`, etc.) or size dimension (`width`, `block`, etc.).
  * `Member<const CSSPrimitiveValue> fallback_`: Optional fallback argument.
* **Semantics**: Always categorized as `kCalcLengthPercentage`. Cannot be resolved at parse time; requires `CSSLengthResolver` connected to LayoutNG's `AnchorEvaluator` during layout.

### 1.5. `CSSMathExpressionKeywordLiteral` (Sizing & Color Channel Keywords)
* **State**: `CSSValueID keyword_` and `Context` (`kMediaProgress`, `kCalcSize`, `kColorChannel`).
* **Semantics**: Supports `calc-size(auto, size * 2)` where `size` acts as a late-bound length variable, or relative color syntax (`rgb(from red calc(r * 2) g b)`).

---

## 2. Supported Operators

Defined in `CSSMathOperator` (`css_math_operator.h`) and mirrored in `CalculationOperator` (`calculation_expression_node.h`).

| `CSSMathOperator` | Arity | W3C Spec Counterpart | Category / Behavior Notes |
| :--- | :--- | :--- | :--- |
| `kAdd` (`+`) | 2 | Sum (`+`) | Commutative, associative (up to float precision). |
| `kSubtract` (`-`) | 2 | Difference (`-`, `+ -B`) | Desugared in W3C to `Add(A, Negate(B))`, kept explicit as binary `kSubtract` in Blink AST. |
| `kMultiply` (`*`) | 2 | Product (`*`) | At least one operand must be `kCalcNumber` (until full unit algebra is enabled). |
| `kDivide` (`/`) | 2 | Quotient (`A * Invert(B)`) | Right operand must be `kCalcNumber` (unless media/container progress division). |
| `kMin` (`min()`) | $1..N$ | `min()` | Variadic. Evaluates to the minimum among operands after canonicalization. |
| `kMax` (`max()`) | $1..N$ | `max()` | Variadic. Evaluates to the maximum among operands after canonicalization. |
| `kClamp` (`clamp()`) | 3 | `clamp(MIN, VAL, MAX)` | Ternary (`operands_[0]=min`, `[1]=val`, `[2]=max`). Supports `none` keyword in W3C L4 (partially supported in Blink). |
| `kRoundNearest` | 2 | `round(nearest, A, B)` | Default rounding strategy if strategy keyword is omitted. |
| `kRoundUp` | 2 | `round(up, A, B)` | $\lceil A / B \rceil \times B$ |
| `kRoundDown` | 2 | `round(down, A, B)` | $\lfloor A / B \rfloor \times B$ |
| `kRoundToZero` | 2 | `round(to-zero, A, B)` | $\text{trunc}(A / B) \times B$ |
| `kMod` | 2 | `mod(A, B)` | Floored modulo; result takes the sign of the divisor $B$. |
| `kRem` | 2 | `rem(A, B)` | Truncated remainder; result takes the sign of the dividend $A$. |
| `kHypot` | $1..N$ | `hypot(A, ...)` | $\sqrt{\sum A_i^2}$. Operands must share a consistent dimension. |
| `kAbs`, `kSign` | 1 | `abs(A)`, `sign(A)` | `abs` preserves category; `sign` accepts any category and outputs `kCalcNumber`. |
| `kProgress`, `kMediaProgress`, `kContainerProgress` | 3 | `progress(V from S to E)` | Computes $(V - S) / (E - S)$, stripping dimensions to yield `kCalcNumber`. |
| `kCalcSize` | 2 | `calc-size(basis, expr)` | Evaluates intrinsic sizing keywords (`auto`, `min-content`) within math expressions. |
| Trigonometric / Exp | 1..2 | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `pow`, `sqrt`, `log`, `exp` | Blink folds these eagerly via `CreateTrigonometricOperation` / `CreateExponentialOperation` or retains them if operands depend on layout/relative lengths. |

---

## 3. Unit Resolution, Type Category Calculus, and Dimension Checking

### 3.1. `CalculationResultCategory` Enumeration
Blink collapses W3C’s multi-dimensional tuple type `[length: L, angle: A, ...]` into a flat enumeration (`CalculationResultCategory`):
* `kCalcNumber`: Dimensionless scalars (`<number>`).
* `kCalcPercent`: Raw percentages (`<percentage>`) before property context resolution.
* `kCalcLength`: Pure physical or font-relative lengths (`px`, `em`, `vw`, `cm`, etc.).
* `kCalcLengthPercentage`: Sum/combination of `<length>` and `<percentage>` (or expressions containing `anchor()`, `min(10px, 20%)`).
* `kCalcAngle`: `deg`, `rad`, `grad`, `turn`.
* `kCalcTime`: `s`, `ms`.
* `kCalcFrequency`: `Hz`, `kHz`.
* `kCalcResolution`: `dpi`, `dpcm`, `dppx`, `x`.
* `kCalcIntrinsicSize`: Used for `calc-size()`.
* `kCalcOther`: Error/invalid state (equivalent to W3C's type checking failure `failure`).

### 3.2. Unit Canonicalization Mapping
Before type-level folding (`ComputeValueInCanonicalUnit`), Blink converts compatible units within a category to a single canonical unit (`CSSPrimitiveValue::CanonicalUnitTypeForCategory`):
* **Length**: `kPixels` (`px`). Fixed conversion ratios: `1in = 96px`, `1cm = 96/2.54 px`, `1mm = 96/25.4 px`, `1Q = 96/101.6 px`, `1pt = 96/72 px`, `1pc = 16px`. Font/viewport units (`em`, `rem`, `vw`, `vh`, `cqw`, etc.) have no parse-time canonical ratio and return `std::nullopt` in `ComputeValueInCanonicalUnit()`, deferring to `CSSLengthResolver`.
* **Angle**: `kDegrees` (`deg`). `1turn = 360deg`, `1grad = 0.9deg`, `1rad = 180/π deg`.
* **Time**: `kSeconds` (`s`). `1ms = 0.001s`. (Note: W3C canonical unit is `s`).
* **Frequency**: `kHertz` (`Hz`). `1kHz = 1000Hz`.
* **Resolution**: `kDotsPerPixel` (`dppx`). `1dpi = 1/96 dppx`, `1dpcm = 2.54/96 dppx`.

### 3.3. The Category Transition Matrix
For binary additive operations (`kAdd`, `kSubtract`), comparison operations (`kMin`, `kMax`, `kClamp`), and stepped-value functions (`kRound*`, `kMod`, `kRem`), Blink enforces category compatibility via `kAddSubtractResult[Category][Category]` in `css_math_expression_node.cc`:

$$\begin{array}{c|cccccccc}
\oplus & \text{Number} & \text{Length} & \text{Percent} & \text{LengthPct} & \text{Angle} & \text{Time} & \text{Freq} & \text{Res} \\
\hline
\text{Number} & \text{Number} & \bot & \bot & \bot & \bot & \bot & \bot & \bot \\
\text{Length} & \bot & \text{Length} & \text{LengthPct} & \text{LengthPct} & \bot & \bot & \bot & \bot \\
\text{Percent} & \bot & \text{LengthPct} & \text{Percent} & \text{LengthPct} & \bot^* & \bot^* & \bot^* & \bot \\
\text{LengthPct} & \bot & \text{LengthPct} & \text{LengthPct} & \text{LengthPct} & \bot & \bot & \bot & \bot \\
\text{Angle} & \bot & \bot & \bot^* & \bot & \text{Angle} & \bot & \bot & \bot \\
\text{Time} & \bot & \bot & \bot^* & \bot & \bot & \text{Time} & \bot & \bot \\
\text{Freq} & \bot & \bot & \bot^* & \bot & \bot & \bot & \text{Freq} & \bot \\
\text{Res} & \bot & \bot & \bot & \bot & \bot & \bot & \bot & \text{Res}
\end{array}$$

*(where $\bot = \text{kCalcOther}$, rejecting the parse).*
*Note on $\bot^*$*: Blink specifically hardcodes `<length-percentage>` into the category enum (`kCalcLengthPercentage`), whereas `<angle-percentage>` or `<time-percentage>` (e.g., in gradients or animations) are handled via contextual flags (`AllowsPercent`) or rejected if mixed directly without context.

### 3.4. Multiplicative Category Rules
* **`kMultiply(L, R)`**:
  * If $L = \text{kCalcNumber}$, result category is $\text{Category}(R)$.
  * If $R = \text{kCalcNumber}$, result category is $\text{Category}(L)$.
  * Otherwise, returns `kCalcOther` (unless unit algebra for `progress()` or `atan2()` is invoked internally).
* **`kDivide(L, R)`**:
  * If $R = \text{kCalcNumber}$, result category is $\text{Category}(L)$.
  * Otherwise, returns `kCalcOther` (except in `CSSMathOperator::kProgress` which divides two matching categories to yield `kCalcNumber`).

---

## 4. Evaluation Mechanics

### 4.1. Dual-Path Evaluation: `double` vs. `CalculationExpressionNode`
1. **Scalar Resolution Path (`ComputeDouble`)**:
   When a property does not accept percentages (or when percentages can be resolved immediately against a known reference value in `CSSLengthResolver`), Blink evaluates the AST bottom-up via `CSSMathExpressionNode::ComputeDouble(const CSSLengthResolver& resolver)`.
   * All arithmetic is performed in standard IEEE 754 double-precision (`double`, 64-bit float).
   * Font-relative lengths (`em