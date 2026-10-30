### 1. Core AST Data Structures in Chromium Blink

In Chromium's Blink rendering engine (`third_party/blink/renderer/core/css/`), media queries are parsed into an immutable, thread-safe AST before being evaluated against the current device and document state.

```
MediaQuerySet
 └── HeapVector<Member<const MediaQuery>>
      ├── RestrictorType (kOnly, kNot, kNone)
      ├── String media_type_ (screen, print, all)
      └── MediaQueryExpNode (AST Root)
           ├── MediaQueryNestedExpNode (Parentheses)
           ├── MediaQueryFunctionExpNode (not, style(), etc.)
           ├── MediaQueryOperatorExpNode (and, or)
           └── MediaQueryFeatureExpNode (Leaf)
                └── MediaQueryExp
                     ├── String media_feature_
                     └── MediaQueryExpBounds
                          ├── MediaQueryExpComparison left_ (value, op)
                          └── MediaQueryExpComparison right_ (value, op)
```

#### `MediaQueryExpValue`
Located in `media_query_exp.h`, `MediaQueryExpValue` represents the right-hand (or left-hand in range contexts) operand of a media feature expression.
* **Internal Representation**: It is a discriminated union (historically a struct with an explicit `Type` enum and a C++ `union` or `std::variant`-like layout) holding:
  * `Type::kInvalid`: Default uninitialized state.
  * `Type::kId`: Holds a `CSSValueID` (e.g., `CSSValueID::kPortrait`, `CSSValueID::kNone`, `CSSValueID::kP3`).
  * `Type::kNumeric`: Holds a `double` value and a `CSSPrimitiveValue::UnitType` (e.g., `kPixels`, `kEms`, `kRems`, `kNumber`, `kDotsPerPixel`).
  * `Type::kRatio`: Holds two `unsigned` or `double` values (`numerator` and `denominator`), representing a `<ratio>` type.
  * `Type::kValue`: Holds a `Member<const CSSValue>` for complex unresolvable expressions (e.g., `calc()`, CSS variables in `style()` queries).

#### `MediaQueryOperator` and `MediaFeaturePrefix`
Blink unifies legacy prefix evaluation (`min-width: 500px`) and Level 4 range syntax (`width >= 500px`, `300px <= width < 800px`) into a single normalized bounding representation (`MediaQueryExpBounds`).
* **Prefix Normalization**: During parsing (`MediaQueryParser`), legacy prefixes `min-` and `max-` are stripped from the feature name (via `MediaFeaturePrefix` logic), and converted into `MediaQueryExpBounds`.
  * `min-width: V` $\longrightarrow$ feature: `width`, `right_` bound: `(V, MediaQueryOperator::kGe)`.
  * `max-width: V` $\longrightarrow$ feature: `width`, `right_` bound: `(V, MediaQueryOperator::kLe)`.
  * `width: V` (no prefix, boolean or exact) $\longrightarrow$ feature: `width`, `right_` bound: `(V, MediaQueryOperator::kEq)` or `(Invalid, kNone)` for boolean context `(width)`.
* **`MediaQueryOperator`**: Enumerates `{ kNone, kEq, kLt, kLe, kGt, kGe }`.
* **`MediaQueryExpBounds`**: Contains two `MediaQueryExpComparison` structs: `left` and `right`. For single bounds (`width > 100px`), `left` is empty (`kNone`) and `right` holds `(100px, kGt)`. For double bounds (`100px < width <= 500px`), `left` holds `(100px, kLt)` and `right` holds `(500px, kLe)`.

#### `MediaQueryExpNode` Hierarchy
To support W3C Media Queries Level 4 recursive boolean logic, Blink replaced its legacy flat vector of `MediaQueryExp` with an AST rooted at `MediaQueryExpNode`:
* `MediaQueryFeatureExpNode`: Leaf node wrapping a `MediaQueryExp`.
* `MediaQueryCompoundExpNode`: Base for binary operators (`MediaQueryAndExpNode`, `MediaQueryOrExpNode`).
* `MediaQueryNotExpNode`: Unary negation node.
* `MediaQueryNestedExpNode`: Preserves parenthetical grouping `( ... )` for serialization (`cssText`).
* `MediaQueryUnknownExpNode`: Represents unparseable or unsupported expressions (`<general-enclosed>`), storing the raw token string to evaluate to `KleeneValue::kUnknown`.

#### `MediaQueryEvaluator`
Located in `media_query_evaluator.h/.cc`, this class executes the AST against a `MediaValues` instance (which abstracts the `LocalFrame`, `Document`, and `ComputedStyle` of the root element).
* It traverses the `MediaQueryExpNode` tree via `Eval(const MediaQueryExpNode&) -> KleeneValue`.
* When hitting a `MediaQueryFeatureExpNode`, it dispatches to a static function table mapping `media_feature_` names (e.g., `media_feature_names::kWidthMediaFeature`) to specific C++ evaluation functions (e.g., `WidthMediaFeatureEval(const MediaQueryExpValue&, MediaQueryOperator, const MediaValues&)`).

---

### 2. Range Context vs. Legacy Prefix Evaluation

W3C Media Queries Level 4 §2.4.3 introduces the **Range Context**, supplementing the legacy `min-` and `max-` prefixes.

#### Canonicalization in Blink
Blink does not maintain separate evaluation paths for `min-width` vs `width >=`. Both are canonicalized at parse time into `MediaQueryExpBounds`.

| CSS Syntax | Canonical Feature | `bounds.left` | `bounds.right` |
| :--- | :--- | :--- | :--- |
| `(width)` | `width` | `(Invalid, kNone)` | `(Invalid, kNone)` |
| `(width: 500px)` | `width` | `(Invalid, kNone)` | `(500px, kEq)` |
| `(min-width: 500px)` | `width` | `(Invalid, kNone)` | `(500px, kGe)` |
| `(max-width: 500px)` | `width` | `(Invalid, kNone)` | `(500px, kLe)` |
| `(width >= 500px)` | `width` | `(Invalid, kNone)` | `(500px, kGe)` |
| `(500px <= width)` | `width` | `(500px, kLe)` | `(Invalid, kNone)` |
| `(300px < width <= 800px)` | `width` | `(300px, kLt)` | `(800px, kLe)` |

#### Orientation Inversion in `left` Bounds
Notice a subtle syntactic vs. semantic detail in `bounds.left`:
In `(300px < width)`, the operator written in CSS is `<`. When Blink evaluates the feature, the feature evaluator function `CompareValue(actual_value, exp_value, op)` expects `actual_value` on the **left** and `exp_value` on the **right** (`actual_value OP exp_value`).
Therefore, when evaluating `bounds.left`, Blink must invert the relational operator before passing it to `CompareValue`:
* `left.op == kLt` (`300px < width`) $\longrightarrow$ evaluated as `width > 300px` (`kGt`).
* `left.op == kLe` (`300px <= width`) $\longrightarrow$ evaluated as `width >= 300px` (`kGe`).
* `left.op == kGt` (`800px > width`) $\longrightarrow$ evaluated as `width < 800px` (`kLt`).
* `left.op == kGe` (`800px >= width`) $\longrightarrow$ evaluated as `width <= 800px` (`kLe`).
* `left.op == kEq` (`500px = width`) $\longrightarrow$ evaluated as `width == 500px` (`kEq`).

For `bounds.IsRange()`, both `left` (if present) and `right` (if present) must evaluate to `true` for the `MediaQueryFeatureExpNode` to evaluate to `KleeneValue::kTrue`.

#### Boolean Context Evaluation (`kNone`)
When a media feature is evaluated without a value or operator, e.g., `@media (color)` or `@media (width)`:
* Per MQ4 §2.4.2, a feature `(F)` evaluates to true if the value of `F` would be non-zero (for numeric/dimension/ratio types) or Anything other than the `none` keyword (for discrete keyword types).
* In Blink, when `op == kNone`, numeric evaluators check `actual_value != 0` (or `actual_value > 0` for non-negative features like `color`, `width`, `monochrome`).

---

### 3. Discrete vs. Continuous Media Features, Ratios, and Lengths

#### Discrete vs. Continuous Features
W3C MQ4 §2.4 classifies every media feature as either **discrete** or **continuous** (range-type):
* **Discrete Features**: Take keyword values and cannot be ordered. Examples: `orientation` (`portrait` | `landscape`), `scan`, `grid`, `update`, `overflow-block`, `overflow-inline`, `color-gamut` (exception: `color-gamut` is discrete in MQ4 despite having a subset hierarchy `srgb` $\subset$ `p3` $\subset$ `rec2020`, though boolean/equality is enforced in syntax), `pointer`, `hover`, `prefers-color-scheme`.
  * *Constraint*: Discrete features reject `<`, `<=`, `>`, `>=` operators and `min-`/`max-` prefixes at parse time. If a user writes `(min-orientation: portrait)` or `(orientation > portrait)`, `MediaQueryParser` rejects the feature expression and wraps it in a `MediaQueryUnknownExpNode`.
* **Continuous (Range) Features**: Take quantitative values (`<length>`, `<number>`, `<integer>`, `<ratio>`, `<resolution>`) and admit total ordering. Examples: `width`, `height`, `device-width`, `device-height`, `aspect-ratio`, `device-aspect-ratio`, `color`, `color-index`, `monochrome`, `resolution`.

#### Ratio Comparison (`aspect-ratio: num / den`)
In CSS MQ4, `<ratio>` is defined as `<number [0,∞]> / <number [0,∞]>` (with MQ4 allowing degenerate ratios like `1/0` or `0/0` in syntax if produced by `calc()`, though literal zeroes were restricted in CSS Values 3 and relaxed/clarified in CSS Values 4).
In Blink (`AspectRatioMediaFeatureEval`):
* The viewport's actual aspect ratio is represented by integer or `LayoutUnit`/float `viewport_width` ($W$) and `viewport_height` ($H$).
* The expression value holds `num` ($N$) and `den` ($D$).
* **Cross-Multiplication vs. Floating-Point**: To avoid floating-point division precision loss (where $16/9 = 1.7777777777777777...$) and division-by-zero traps, Blink compares ratios via cross-multiplication:
  $$\frac{W}{H} \bowtie \frac{N}{D} \iff W \times D \bowtie N \times H$$
  Specifically, in `CompareAspectRatioValue`:
  `CompareDoubleValue(static_cast<double>(width) * exp_den, static_cast<double>(height) * exp_num, op)`.
  Because $W, H, N, D$ are cast to IEEE 754 `double` (53-bit mantissa) before multiplication, exact integer cross-products up to $2^{53} - 1$ ($9 \times 10^{15}$) are preserved without rounding error.

#### Length Comparisons and Viewport Units (`px`, `em`, `rem`)
When evaluating `width`, `height`, `device-width`, or `device-height`, the `MediaQueryExpValue` can be specified in any `<length>` unit (`px`, `em`, `rem`, `cm`, `in`, `vw`, `vh`, `ch`, `ex`, `cap`, `ic`, `lh`).
* **Crucial Spec Rule (MQ4 §6)**: Relative length units in Media Queries (`em`, `rem`, `ch`, `ex`, `lh`, etc.) are **always** resolved against the **initial value** of the font properties (or user-agent default font size, typically `16px`), **never** the author-styled `:root` (`<html>`) `font-size`.
  * *Why?* If `@media (min-width: 50rem)` depended on `html { font-size: 20px }`, and inside that `@media` block the author wrote `html { font-size: 10px }`, it would create an unresolvable circularity (oscillation loop).
* **Blink Implementation (`MediaValues::ComputeLength`)**:
  * `MediaValues` queries `DefaultFontSize()` from `Settings` (defaulting to `16.0f`, modified only by browser preferences or `text-autosizing`/page zoom settings, ignoring author CSS rules).
  * `1em` == `1rem` == `DefaultFontSize()` (in CSS pixels).
  * Physical units (`in`, `cm`, `mm`, `pt`, `pc`, `Q`) are converted using the fixed CSS ratio (`1in = 96px`, `1pt = 96/72 px`).
  * The viewport width/height in `MediaValues` is stored in CSS pixels (`double` or `int` depending on subpixel zoom). If the browser zoom level is $Z$, `MediaValues` divides the physical device viewport pixel dimension by $Z$ so that media queries evaluate in zoom-adjusted CSS pixels.

---

### 4. Three-Valued Logic Calculus (Kleene Logic)

W3C Media Queries Level 4 §3.1 mandates that media query conditions be evaluated using ** Kleene 3-valued logic** ($\mathcal{K}_3 = \{\mathbf{T}, \mathbf{F}, \mathbf{U}\}$), where $\mathbf{U}$ represents `unknown`.

In Blink (`media_query_evaluator.h`), this is represented by:
```cpp
enum class KleeneValue {
  kTrue,
  kFalse,
  kUnknown,
};
```

#### Truth Tables (MQ4 §3.1)

**Negation (`not`)**:
| $A$ | $\neg A$ |
| :---: | :---: |
| $\mathbf{T}$ | $\mathbf{F}$ |
| $\mathbf{F}$ | $\mathbf{T}$ |
| $\mathbf{U}$ | $\mathbf{U}$ |

**Conjunction (`and`)**: $\mathbf{F}$ dominates $\mathbf{U}$.
| $A \land B$ | $\mathbf{T}$ | $\mathbf{F}$ | $\mathbf{U}$ |
| :---: | :---: | :---: | :---: |
| $\mathbf{T}$ | $\mathbf{T}$ | $\mathbf{F}$ | $\mathbf{U}$ |
| $\mathbf{F}$ | $\mathbf{F}$ | $\mathbf{F}$ | $\mathbf{F}$ |
| $\mathbf{U}$ | $\mathbf{U}$ | $\mathbf{F}$ | $\mathbf