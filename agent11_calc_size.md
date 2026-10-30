# Formal Audit Report: Chromium Blink `calc-size()` & `progress()` vs. W3C CSS Values and Units Level 4

**Auditor**: Agent 11  
**Target Subsystem**: Chromium Blink CSS Math Expression Engine (`third_party/blink/renderer/core/css/`, `third_party/blink/renderer/platform/geometry/`)  
**Specification Reference**: W3C CSS Values and Units Module Level 4 (Sections 10.6 `progress()`, 10.7 `calc-size()`)

---

## 1. Core Data Structures in Blink CSS Math Extensions

In Chromium Blink, mathematical expressions are parsed into an AST rooted at `CSSMathExpressionNode`, which is later lowered into platform-level `CalculationExpressionNode` trees for layout evaluation.

### 1.1 Parse-Time AST (`core/css/css_math_expression_node.h`)

*   **`CSSMathExpressionOperation` (Handling `calc-size()` and `progress()`)**:
    Blink models both `calc-size()` and `progress()` not as dedicated subclasses of `CSSMathExpressionNode`, but as variants of `CSSMathExpressionOperation` distinguished by `CSSMathOperator`:
    *   `CSSMathOperator::kCalcSize`: Represents a binary operation where `operands_[0]` is the *basis* (`CSSMathExpressionNode`) and `operands_[1]` is the *calculation* (`CSSMathExpressionNode`).
    *   `CSSMathOperator::kProgress`, `CSSMathOperator::kMediaProgress`, `CSSMathOperator::kContainerProgress`: Ternary operations where `operands_[0]` is the *progress value*, `operands_[1]` is the *start* ($A$), and `operands_[2]` is the *end* ($B$).
*   **`CSSMathExpressionKeywordLiteral`**:
    A specialized node representing sizing keywords inside math expressions. It stores a `CSSValueID` (`keyword_`) and a `Context` enum:
    *   `Context::kCalcSize`: Represents `auto`, `min-content`, `max-content`, `fit-content`, `stretch` (or `-webkit-fill-available`), `any`, and the bound variable `size`.
    *   `Context::kMediaProgress` / `Context::kContainerProgress`: Represents feature keywords like `width` or `height` evaluated against the viewport or container.
*   **`CSSMathExpressionIdentifierLiteral` (`CSSCalcSymbolToken`)**:
    Used during parsing (`css_math_expression_node.cc`) to capture unquoted identifiers (like `size` in `calc-size()` or channel keywords in relative color syntax) via a symbol table (`CSSCalcSymbolTable`) before resolving them into `CSSMathExpressionKeywordLiteral` or numeric literals.

### 1.2 Layout-Time Evaluation AST (`platform/geometry/calculation_expression_node.h`)

When a `CSSMathExpressionNode` is converted to a `Length` via `ToCalculationValue()`, Blink constructs a thread-safe, ref-counted `CalculationExpressionNode` tree:

*   **`CalculationExpressionOperationNode`**:
    Mirrors `CSSMathExpressionOperation` using `CalculationOperator::kCalcSize` (2 children) and `CalculationOperator::kProgress` (3 children).
*   **`CalculationExpressionSizingKeywordNode`**:
    Terminal node holding a `Keyword` enum (`kSize`, `kAny`, `kAuto`, `kMinContent`, `kMaxContent`, `kFitContent`, `kStretch`).

---

## 2. Calculation and Evaluation Semantics

### 2.1 `calc-size( <calc-size-basis>, <calc-sum>? )`

**W3C Specification**:
1.  If `<calc-sum>` is omitted, it defaults to the keyword `size`.
2.  The `<calc-size-basis>` can be an intrinsic sizing keyword (`auto`, `min-content`, `max-content`, `fit-content`, `stretch`), the keyword `any`, a nested `calc-size()`, or a `<calc-sum>` resolving to a `<length-percentage>`.
3.  If the basis is *not* `any`, the keyword `size` is valid within the `<calc-sum>` and evaluates to the resolved layout size of the basis.
4.  **Interpolation**: Two `calc-size()` values can interpolate if and only if their underlying bases are identical, or one of the bases is `any`. If a basis is herself a nested `calc-size(B1, C1)` inside `calc-size(B_nested, C2)`, it simplifies by substituting `C1` for `size` inside `C2`, lifting `B1` as the canonical basis.

**Blink Implementation (`CalculationExpressionOperationNode::Evaluate`)**:
During layout (`Length::Evaluate(float max_value, const EvaluationInput& input)`), `EvaluationInput` provides an optional `size_keyword_basis` callback/value:
```cpp
// Conceptual flow in CalculationExpressionOperationNode::Evaluate for kCalcSize:
float basis_value = children_[0]->Evaluate(max_value, input);
EvaluationInput calculation_input(input);
calculation_input.size_keyword_basis = basis_value;
return children_[1]->Evaluate(max_value, calculation_input);
```
When `CalculationExpressionSizingKeywordNode::Evaluate` encounters `Keyword::kSize`, it returns `*input.size_keyword_basis`. If it encounters an intrinsic keyword (`kAuto`, `kMinContent`, etc.), it invokes the layout-provided `IntrinsicSizeEvaluator` callback stored in `EvaluationInput`.

### 2.2 `progress( <calc-sum> from <calc-sum> to <calc-sum> )`

*(Note: W3C CSS Values 4 updated syntax from `from/to` to comma-separated `progress(val, start, end)`, though Blink supports or is transitioning between both syntax forms in `CSSMathExpressionNodeParser::ParseProgressNotation`).*

**W3C Specification & Blink Evaluation**:
1.  All three arguments must resolve to the same canonical type (`<number>`, `<length>`, `<percentage>`, `<angle>`, `<time>`, `<frequency>`, `<resolution>`).
2.  Given evaluated canonical floating-point values $V$ (value), $A$ (start), and $B$ (end), the raw progress is:
    $$\text{progress}(V, A, B) = \frac{V - A}{B - A}$$
3.  The result is always a unitless `<number>` (`kCalcNumber`). Note that `progress()` itself **does not clamp** its output to $[0, 1]$; clamping is reserved for `clamp(0, progress(...), 1)` or when used as an interpolation progress in `mix()` / `calc-mix()`.

---

## 3. Division by Zero and `NaN` / `Infinity` Clamping

According to **CSS Values and Units Level 4 § 10.9 (Type Checking and `NaN`/`Infinity` Handling)**:
*   IEEE 754 floating-point semantics apply during intermediate calculations inside a math tree.
*   In `progress(V, A, B)`, if $A = B$:
    *   If $V = A = B$, then $\frac{0}{0} = \text{NaN}$.
    *   If $V > A$, then $\frac{V - A}{0} = +\infty$.
    *   If $V < A$, then $\frac{V - A}{0} = -\infty$.
*   If $V, A,$ or $B$ is $\pm\infty$ (e.g., `progress(100px from 0px to calc(1px / 0))`), then:
    *   $\frac{\text{finite}}{\pm\infty} = \pm 0.0$.
    *   $\frac{\pm\infty}{\pm\infty} = \text{NaN}$.
*   **Top-Level Clamping**: `NaN` and $\pm\infty$ are preserved across intermediate AST nodes (so `calc(0 * progress(0, 0, 0))` evaluates `0 * NaN = NaN`), and are only censored/clamped at the *top-level* exit of the calculation tree (`CSSPrimitiveValue::ClampToCSSLengthRange` or `ClampTo<float>`):
    *   $\text{NaN} \mapsto 0.0$
    *   $+\infty \mapsto \text{std::numeric\_limits<float>::max()}$ (or layout `LayoutUnit::Max()`)
    *   $-\infty \mapsto \text{std::numeric\_limits<float>::lowest()}$ (or `LayoutUnit::Min()`)

---

## 4. Mathematical Invariants, Edge Cases, and Implementation Gaps

### 4.1 Mathematical Invariants
1.  **Progress Monotonicity**:
    *   If $A < B$, then for all finite $V_1 \le V_2$, $\text{progress}(V_1, A, B) \le \text{progress}(V_2, A, B)$.
    *   If $A > B$, then for all finite $V_1 \le V_2$, $\text{progress}(V_1, A, B) \ge \text{progress}(V_2, A, B)$ (anti-monotonic).
2.  **Boundedness under Defined Ranges**:
    *   If $A < B$ and $V \in [A, B]$, then $\text{progress}(V, A, B) \in [0, 1]$.
    *   If $A > B$ and $V \in [B, A]$, then $\text{progress}(V, A, B) \in [0, 1]$.
3.  **`calc-size()` Basis Substitution Soundness (Associativity of Nesting)**:
    *   Let $\llbracket E \rrbracket_{\rho, b}$ denote the evaluation of expression $E$ under environment $\rho$ (mapping intrinsic keywords to floats) and bound `size` value $b \in \mathbb{R}_\bot$.
    *   For a nested basis `calc-size( calc-size(B, E1), E2 )`, evaluating the nested structure directly is extensionally equivalent to substituting $E_1$ for every free occurrence of `size` in $E_2$ with basis $B$:
        $$\llbracket \text{calc-size}(\text{calc-size}(B, E_1), E_2) \rrbracket_{\rho, \bot} = \llbracket \text{calc-size}(B, E_2[E_1 / \text{size}]) \rrbracket_{\rho, \bot}$$

### 4.2 Edge Cases & Audited Implementation Gaps in Blink

1.  **Gap 1: Premature Simplification / Folding of `progress()` with Percentage Operands**:
    *   In Blink's `CSSMathExpressionNodeParser::ParseProgressNotation`, if the arguments are `<length-percentage>` (e.g., `progress(50% from 10px to 100px)`), they cannot be resolved at parse time (`ComputeValueInCanonicalUnit` returns `std::nullopt`). Blink constructs a `CalculationExpressionOperationNode` of type `kProgress`. However, `CSSMathExpressionOperation::CreateArithmeticOperationSimplified` occasionally attempts constant folding on homogeneous percentage trees (`progress(50% from 0% to 100%)`). If the percentage basis during layout is **negative** (possible in flex/grid overflow or negative margins), simplifying `progress(50% from 0% to 100%)` to `0.5` at parse time is sound, *unless* the percentage basis is `0px`, where runtime evaluation would yield $\frac{0 - 0}{0 - 0} = \text{NaN} \mapsto 0.0$, whereas parse-time percentage stripping yields $\frac{50 - 0}{100 - 0} = 0.5$!
    *   **Verdict**: *Spec / Implementation Divergence on 0px Percentage Basis.*
2.  **Gap 2: `calc-size(any, ...)` Usage of `size` Keyword Validation**:
    *   The W3C specification states that if the `<calc-size-basis>` is `any` (or a nested `calc-size()` whose innermost basis is `any`), the `<calc-sum>` **must not** contain the `size` keyword (it is a parse error).
    *   In Blink, `ParseCalcSize` checks if the immediate first argument is the identifier `any` before populating the `CSSCalcSymbolTable` with `size`. However, if the first argument is a nested `calc-size(any, 100px)`, `HasSizeKeyword` check on the basis must recursively inspect the innermost basis to forbid `size` in the outer calculation.
3.  **Gap 3: Fast-Floats (`-ffast-math`) vs. Strict IEEE 754 `NaN` Propagation**:
    *   In `CalculationExpressionOperationNode::Evaluate` for `kProgress`, Blink computes `(progress - start) / (end - start)`. If compiled with flags or platform optimizations that flush NaNs or assume finite math, `(0.0f - 0.0f) / (0.0f - 0.0f)` can behave unpredictably if not explicitly guarded with `std::isnan` before top-level clamping.

---

## 5. Formal Verification in Rocq / Coq (`BlinkCalcSizeProgressSemantics.v`)

Below is a complete, self-contained Rocq (Coq) formalization modeling Blink's `calc-size()` and `progress()` AST, IEEE-754 extended real evaluation (`R_ext` with `NaN`, `PosInf`, `NegInf`), top-level CSS clamping, basis substitution, and machine-checked proofs of the core invariants and the percentage folding edge case.

```coq
(** * BlinkCalcSizeProgressSemantics.v
    Formal Verification of Chromium Blink CSS calc-size() and progress()
    against W3C CSS Values and Units Module Level 4.
    Auditor: Agent 11 *)

From Coq Require Import Reals Lra List Bool Arith.
Import ListNotations.
Open Scope R_scope.

(** ** 1. Extended Real Numbers (Modeling IEEE-754 NaN / Infinity in CSS) *)

Inductive R_ext : Type :=
  | R_Fin (r : R)
  | R_PosInf
  | R_NegInf
  | R_NaN.

Definition r_ext_add (x y : R_ext) : R_ext :=
  match x, y with
  | R_Fin a, R_Fin b => R_Fin (a + b)
  | R_PosInf, R_Fin _ | R_Fin _, R_PosInf | R_PosInf, R_PosInf => R_PosInf
  | R_NegInf, R_Fin _ | R_Fin _, R_NegInf | R_NegInf, R_NegInf => R_NegInf
  | _, _ => R_NaN
  end.

Definition r_ext_sub (x y : R_ext) : R_ext :=
  match x, y with
  | R_Fin a, R_Fin b => R_Fin (a - b)
  | R_PosInf, R_Fin _ | R_Fin _, R_NegInf | R_PosInf, R_NegInf => R_PosInf
  | R_NegInf, R_Fin _ | R_Fin _, R_PosInf | R_NegInf, R_PosInf => R_NegInf
  | _, _ => R_NaN
  end.

Definition r_ext_mul (x y : R_ext) : R_ext :=
  match x, y with
  