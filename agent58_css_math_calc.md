# Audit Report: Agent 58
**Target:** Chromium Blink CSS Math Expression Engine (`third_party/blink/renderer/core/css/css_math_expression_node.h/.cc`)  
**Specification:** W3C CSS Values and Units Module Level 4, §10.2 (Basic Arithmetic: `calc()`) & §10.3 (Comparison Functions: `min()`, `max()`, `clamp()`)  
**Verification Target:** `BlinkCSSMathCalcSemantics.v`

---

## 1. Core Data Structures in Blink Math Expressions

In Chromium's Blink rendering engine, mathematical expressions parsed from CSS `calc()`, `min()`, `max()`, and `clamp()` functions are represented as an Abstract Syntax Tree (AST) rooted at the abstract base class `CSSMathExpressionNode`.

### 1.1 `CSSMathExpressionNode` (Base Class)
Located in `css_math_expression_node.h`, this class encapsulates the resolved category (`CalculationCategory`, e.g., `kCalcNumber`, `kCalcLength`, `kCalcPercent`, `kCalcPercentLength`) and provides virtual interfaces for evaluation and serialization:
* `virtual double DoubleValue() const`: Evaluates canonical unit literals or pure numbers.
* `virtual std::optional<PixelsAndPercent> ToPixelsAndPercent(const CSSLengthResolver&) const`: Evaluates length/percentage trees against layout context.
* ` scoped_refptr<const CalculationExpressionNode> ToCalculationExpression(const CSSLengthResolver&) const`: Lowers the CSS AST into a platform-level `CalculationExpressionNode` tree for deferred layout evaluation (when percentages cannot be resolved at parse time).

### 1.2 `CSSMathExpressionNumericLiteral` (Leaf Node)
Represents a terminal numeric value paired with a unit type (`CSSPrimitiveValue::UnitType`).
* **Fields:** `Member<const CSSNumericLiteralValue> value_`.
* **Invariants:** Holds a raw IEEE 754 `double` and a unit tag. During parse-time simplification, compatible units (e.g., `px` and `cm`, `deg` and `rad`) are converted to their canonical unit (e.g., `px` for lengths, `deg` for angles) via `CSSPrimitiveValue::ConversionToCanonicalUnitsScaleFactor`.

### 1.3 `CSSMathExpressionOperation` (Internal Node)
Represents an $n$-ary or binary mathematical operation over child nodes.
* **Fields:**
  * `Operands operands_` (`HeapVector<Member<const CSSMathExpressionNode>>`): A vector of child AST nodes. Binary arithmetic operations (`kAdd`, `kSubtract`, `kMultiply`, `kDivide`) enforce `operands_.size() == 2`, whereas comparison operations (`kMin`, `kMax`) and variadic sum/product normalizations allow $N \ge 1$ operands.
  * `CSSMathOperator operator_`: Enumerates the operation:
    * `CSSMathOperator::kAdd` (`+`)
    * `CSSMathOperator::kSubtract` (`-`)
    * `CSSMathOperator::kMultiply` (`*`)
    * `CSSMathOperator::kDivide` (`/`)
    * `CSSMathOperator::kMin` (`min(...)`)
    * `CSSMathOperator::kMax` (`max(...)`)
    * `CSSMathOperator::kClamp` (`clamp(...)` — Note: Blink supports both explicit `kClamp` nodes for serialization fidelity and canonical desugaring during value computation).

---

## 2. `clamp()` Definition and Normalization

Per **CSS Values Level 4 §10.3**, `clamp(MIN, VAL, MAX)` represents a value clamped between an upper and lower bound.

### 2.1 Specification Equivalence
The specification defines `clamp(MIN, VAL, MAX)` as identically equivalent to:
$$\operatorname{max}(\text{MIN}, \operatorname{min}(\text{VAL}, \text{MAX}))$$

Notice the asymmetry when $\text{MIN} > \text{MAX}$:
$$\operatorname{max}(\text{MIN}, \operatorname{min}(\text{VAL}, \text{MAX})) = \text{MIN} \quad (\text{when } \text{MIN} > \text{MAX})$$
This matches the CSS Values 4 specification requirement: *"If MIN is greater than MAX, then the function resolves to MIN."*

### 2.2 Blink Normalization & Evaluation Semantics
In Blink (`CSSMathExpressionOperation::CreateComparisonFunctionSimplified` and `EvaluateOperator`), when `clamp(min_val, val, max_val)` is evaluated over resolved scalars:
1. First, `std::min(val, max_val)` is computed (resolving the upper bound).
2. Next, `std::max(min_val, std::min(val, max_val))` is computed (resolving the lower bound, which dominates if `min_val > max_val`).
3. In the formal verification layer, modeling `EClamp min_e val_e max_e` directly via the desugaring `EMax min_e (EMin val_e max_e)` guarantees exact structural compliance with §10.3.

---

## 3. Evaluation Algebra & Simplification Rules

Blink's `CSSMathExpressionOperation::CreateArithmeticOperationSimplified` implements eager parse-time algebraic simplification as mandated by **CSS Values Level 4 §10.10 (Simplifying Calculation Trees)**:

1. **Constant Folding:**
   If both operands of a binary operation (`Add`, `Subtract`, `Multiply`, `Divide`) or all operands of a comparison (`Min`, `Max`) are `CSSMathExpressionNumericLiteral` nodes with identical canonical units, Blink immediately computes the result and returns a single `CSSMathExpressionNumericLiteral`.
2. **Division by Scalar Conversion:**
   For `A / B` where `B` is a resolved non-zero dimensionless number, Blink rewrites or folds `A / B` into `A * (1 / B)` when simplifying over sum nodes, or directly scales `A` if `A` is a literal. (In exact real/rational semantics without IEEE 754 rounding errors, division is the exact multiplicative inverse).
3. **Associativity of Addition and Multiplication:**
   $$\text{eval}((A + B) + C) = \text{eval}(A + (B + C))$$
   $$\text{eval}((A \times B) \times C) = \text{eval}(A \times (B \times C))$$
   Blink flattens nested additive and multiplicative trees into canonical sum-of-products forms (`AddSubValue` / `MultiplyValue` in `css_math_expression_node.cc`) to combine like terms (e.g., `10px + 20% + 5px` $\to$ `15px + 20%`).
4. **Distributivity of Multiplication over Addition/Subtraction:**
   $$\text{eval}(A \times (B \pm C)) = \text{eval}((A \times B) \pm (A \times C))$$
   When multiplying a scalar literal across an additive node (e.g., `2 * (10px + 50%)`), Blink distributes the multiplication across the children to yield `20px + 100%`.

---

## 4. Mathematical Invariants

 Over the ordered field of real numbers $\mathbb{R}$ (or exact rationals $\mathbb{Q}$ representing canonicalized layout units free of NaN/Infinity):

1. **Determinism of Evaluation:**
   Evaluation is a pure total function (modulo division by zero, which is prevented at parse time for literal zero divisors or handled via totalized field semantics in Coq where $x / 0 = 0$):
   $$\forall e\; v_1\; v_2,\; \text{eval}(e) = v_1 \land \text{eval}(e) = v_2 \implies v_1 = v_2$$
2. **`clamp` Bounds Satisfaction:**
   Whenever the lower bound does not exceed the upper bound ($\text{min\_val} \le \text{max\_val}$), the evaluated `clamp` expression is strictly bounded within $[\text{min\_val}, \text{max\_val}]$:
   $$\text{min\_val} \le \text{max\_val} \implies \text{min\_val} \le \operatorname{clamp}(\text{min\_val}, \text{val}, \text{max\_val}) \le \text{max\_val}$$
3. **`clamp` Lower-Bound Dominance (Inversion Invariant):**
   Per CSS Values 4 §10.3, if $\text{min\_val} > \text{max\_val}$, the result resolves to $\text{min\_val}$:
   $$\text{max\_val} \le \text{min\_val} \implies \operatorname{clamp}(\text{min\_val}, \text{val}, \text{max\_val}) = \text{min\_val}$$
4. **`clamp` Idempotence:**
   Clamping an already clamped value with the same bounds is an identity operation:
   $$\operatorname{clamp}(\text{min\_val}, \operatorname{clamp}(\text{min\_val}, \text{val}, \text{max\_val}), \text{max\_val}) = \operatorname{clamp}(\text{min\_val}, \text{val}, \text{max\_val})$$

---

## 5. Formalization in Rocq / Coq (`BlinkCSSMathCalcSemantics.v`)

Below is the self-contained, fully proven Rocq/Coq formalization of Blink's CSS Math AST, constant folding pass, evaluation algebra, and `clamp`/`min`/`max` invariants over $\mathbb{R}$ (`Reals`).

```coq
(** * BlinkCSSMathCalcSemantics.v
    Formal Audit & Verification of Chromium Blink CSS Math Expressions
    (calc, min, max, clamp) against W3C CSS Values and Units Module Level 4 (§10.2 & §10.3).
    Agent 58 Verification Artifact. *)

From Coq Require Import Reals Lra.
Local Open Scope R_scope.

(* ========================================================================== *)
(** ** 1. Core Data Structures (Blink CSSMathExpressionNode AST)             *)
(* ========================================================================== *)

(** Represents Blink's [CSSMathOperator] for binary and comparison nodes. *)
Inductive CSSMathExpressionNode : Type :=
  | CSSMathExpressionNumericLiteral (v : R)
  | CSSMathExpressionAdd (l r : CSSMathExpressionNode)
  | CSSMathExpressionSubtract (l r : CSSMathExpressionNode)
  | CSSMathExpressionMultiply (l r : CSSMathExpressionNode)
  | CSSMathExpressionDivide (l r : CSSMathExpressionNode)
  | CSSMathExpressionMin (l r : CSSMathExpressionNode)
  | CSSMathExpressionMax (l r : CSSMathExpressionNode).

(** ** 2. [clamp()] Definition and Canonical Normalization (§10.3)            *)

(** Per CSS Values Level 4 §10.3, [clamp(min_val, val, max_val)] is defined as
    [max(min_val, min(val, max_val))]. *)
Definition CSSMathExpressionClamp
  (min_node val_node max_node : CSSMathExpressionNode) : CSSMathExpressionNode :=
  CSSMathExpressionMax min_node (CSSMathExpressionMin val_node max_node).

(** Semantic clamp over resolved scalars. *)
Definition Rclamp (min_val val max_val : R) : R :=
  Rmax min_val (Rmin val max_val).

(* ========================================================================== *)
(** ** 3. Evaluation Semantics & Constant Folding Algebra                     *)
(* ========================================================================== *)

(** Denotational evaluation of [CSSMathExpressionNode] to canonical real values.
     closely mirrors [CSSMathExpressionNode::DoubleValue()] and
    [CSSMathExpressionOperation::EvaluateOperator()]. *)
Fixpoint eval (e : CSSMathExpressionNode) : R :=
  match e with
  | CSSMathExpressionNumericLiteral v => v
  | CSSMathExpressionAdd l r          => eval l + eval r
  | CSSMathExpressionSubtract l r     => eval l - eval r
  | CSSMathExpressionMultiply l r     => eval l * eval r
  | CSSMathExpressionDivide l r       => eval l / eval r
  | CSSMathExpressionMin l r          => Rmin (eval l) (eval r)
  | CSSMathExpressionMax l r          => Rmax (eval l) (eval r)
  end.

(** Parse-time constant folding simplification pass, mirroring Blink's
    [CreateArithmeticOperationSimplified] and [CreateComparisonFunctionSimplified]. *)
Fixpoint simplify_const_fold (e : CSSMathExpressionNode) : CSSMathExpressionNode :=
  match e with
  | CSSMathExpressionNumericLiteral v => CSSMathExpressionNumericLiteral v
  | CSSMathExpressionAdd l r =>
      match simplify_const_fold l, simplify_const_fold r with
      | CSSMathExpressionNumericLiteral vl, CSSMathExpressionNumericLiteral vr =>
          CSSMathExpressionNumericLiteral (vl + vr)
      | sl, sr => CSSMathExpressionAdd sl sr
      end
  | CSSMathExpressionSubtract l r =>
      match simplify_const_fold l, simplify_const_fold r with
      | CSSMathExpressionNumericLiteral vl, CSSMathExpressionNumericLiteral vr =>
          CSSMathExpressionNumericLiteral (vl - vr)
      | sl, sr => CSSMathExpressionSubtract sl sr
      end
  | CSSMathExpressionMultiply l r =>
      match simplify_const_fold l, simplify_const_fold r with
      | CSSMathExpressionNumericLiteral vl, CSSMathExpressionNumericLiteral vr =>
          CSSMathExpressionNumericLiteral (vl * vr)
      | sl, sr => CSSMathExpressionMultiply sl sr
      end
  | CSSMathExpressionDivide l r =>
      match simplify_const_fold l, simplify_const_fold r with
      | CSSMathExpressionNumericLiteral vl, CSSMathExpressionNumericLiteral vr =>
          CSSMathExpressionNumericLiteral (vl / vr)
      | sl, sr => CSSMathExpressionDivide sl sr
      end
  | CSSMathExpressionMin l r =>
      match simplify_const_fold l, simplify_const_fold r with
      | CSSMathExpressionNumericLiteral vl, CSSMathExpressionNumericLiteral vr =>
          CSSMathExpressionNumericLiteral (Rmin vl vr)
      | sl, sr => CSSMathExpressionMin sl sr
      end
  | CSSMathExpressionMax l r =>
      match simplify_const_fold l, simplify_const_fold r with
      | CSSMathExpressionNumericLiteral vl, CSSMathExpressionNumericLiteral vr =>
          CSSMathExpressionNumericLiteral (Rmax vl vr)
      | sl, sr => CSSMathExpressionMax sl sr
      end
  end.

(** *** 3.1 Soundness of Constant Folding *)
Theorem simplify_const_fold_sound : forall (e : CSSMathExpressionNode),
  eval (simplify_const_fold e) = eval e.
Proof.
  induction e; simpl; auto;
  destruct (simplify_const_fold e1); destruct (simplify_const_fold e2);
  simpl in *; congruence.
Qed.

(** *** 3.2 Associativity & Distributivity Laws *)
Theorem eval_add_assoc : forall a b c : CSSMathExpressionNode,
  eval (CSSMathExpressionAdd (CSSMathExpressionAdd a b) c) =
  eval (CSSMathExpressionAdd a (CSSMathExpressionAdd b c)).
Proof.
  intros; simpl; lra.
Qed.

Theorem eval_mul_assoc : forall a b c : CSSMathExpressionNode,
  eval (CSSMathExpressionMultiply (CSSMathExpressionMultiply a b) c) =
