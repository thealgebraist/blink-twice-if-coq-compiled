### 1. Core Data Structures in Blink Math Functions

In Chromium's Blink engine (`third_party/blink/renderer/core/css/`), stepped value math functions (`round()`, `mod()`, `rem()`) are parsed into AST nodes governed by the `CSSMathExpressionNode` class hierarchy.

#### `CSSMathOperator` (`css_math_operator.h`)
Blink decomposes the four rounding strategies of `round(<rounding-strategy>?, A, B)` directly into distinct operators at parse time, alongside `mod` and `rem`:
```cpp
enum class CSSMathOperator {
  kAdd,
  kSubtract,
  kMultiply,
  kDivide,
  kMin,
  kMax,
  kClamp,
  kRoundNearest, // round(nearest, A, B) or round(A, B)
  kRoundUp,      // round(up, A, B)
  kRoundDown,    // round(down, A, B)
  kRoundToZero,  // round(to-zero, A, B)
  kMod,          // mod(A, B)
  kRem,          // rem(A, B)
  // ... trigonometric & exponential operators ...
  kInvalid
};
```

#### `CSSMathExpressionOperation` (`css_math_expression_node.h`)
The AST representation for these operations is encapsulated in `CSSMathExpressionOperation`:
```cpp
class CORE_EXPORT CSSMathExpressionOperation final : public CSSMathExpressionNode {
 public:
  using Operands = HeapVector<Member<const CSSMathExpressionNode>>;
  
  CSSMathExpressionOperation(const CSSMathExpressionNode* left_side,
                             const CSSMathExpressionNode* right_side,
                             CSSMathOperator op,
                             CSSPrimitiveValue::ValueRange);
  // ...
 private:
  Operands operands_; // Always size 2 for Stepped Value functions: [0] = A (value/dividend), [1] = B (step/divisor)
  const CSSMathOperator operator_;
};
```
During parsing (`CSSPropertyParserHelpers::ConsumeMathFunction`), if the first token inside `round(...)` is an ident matching `nearest`, `up`, `down`, or `to-zero`, it selects the respective `CSSMathOperator::kRound*` enum and consumes the comma. If omitted, it defaults to `kRoundNearest`. Both operands $A$ and $B$ must resolve to the same `CalculationResultCategory` (e.g., `kCalcLength`, `kCalcNumber`, `kCalcAngle`), checked via `CheckSameType()`.

For layout-dependent lengths (e.g., `round(100%, 20px)`), Blink converts the `CSSMathExpressionNode` tree into a `CalculationExpressionNode` (`CalculationExpressionOperationNode` with `CalculationOperator` equivalents) located in `third_party/blink/renderer/platform/geometry/calculation_expression_node.h` for evaluation during layout.

---

### 2. Evaluation Semantics: Blink vs. CSS Values and Units Level 4 §10.4

In Blink (`css_math_expression_node.cc` and `calculation_expression_node.cc`), evaluation is dispatched via `EvaluateSteppedValueFunction` or `EvaluateOperator`:

#### `round(<rounding-strategy>, A, B)`
Per CSS Values 4 §10.4, `round(A, B)` rounds $A$ to an integer multiple of $B$:
*   **Lower multiple ($L$):** $B \cdot \lfloor A / B \rfloor$ (where $B > 0$) or more generally the greatest integer multiple of $|B|$ less than or equal to $A$: $|B| \cdot \lfloor A / |B| \rfloor$.
*   **Upper multiple ($U$):** $|B| \cdot \lceil A / |B| \rceil$.

In Blink's C++ implementation (using double-precision IEEE 754 floating-point):
*   **`kRoundUp` (`up`):** Rounds toward $+\infty$.
    $$\text{result} = U = |B| \cdot \lceil A / |B| \rceil$$
*   **`kRoundDown` (`down`):** Rounds toward $-\infty$.
    $$\text{result} = L = |B| \cdot \lfloor A / |B| \rfloor$$
*   **`kRoundToZero` (`to-zero`):** Rounds toward $0$.
    $$\text{result} = \begin{cases} L & \text{if } A \ge 0 \\ U & \text{if } A < 0 \end{cases} = |B| \cdot \text{trunc}(A / |B|)$$
*   **`kRoundNearest` (`nearest`):** Rounds to the multiple closer to $A$. In the event of a tie ($A - L = U - A$, i.e., $A / |B| = k + 0.5$), CSS Values 4 specifies breaking ties toward $+\infty$ ( memilih $U$).
    *   *Audit Note:* Standard `std::round(x)` rounds half-way cases *away from zero*, which violates CSS spec for negative ties (e.g., `round(-1.5, 1)` must be `-1`, not `-2`). Blink handles this by computing `std::floor((A / std::abs(B)) + 0.5)` or explicitly comparing distances `U - A <= A - L ? U : L`.

#### `mod(A, B)`
Evaluates the modulus where the result takes the sign of the divisor $B$:
$$\text{mod}(A, B) = A - B \cdot \lfloor A / B \rfloor$$
In Blink:
```cpp
double quotient = std::floor(a / b);
return a - b * quotient; // With edge-case guards for infinities/NaNs
```

#### `rem(A, B)`
Evaluates the remainder where the result takes the sign of the dividend $A$:
$$\text{rem}(A, B) = A - B \cdot \text{trunc}(A / B)$$
In Blink, this maps directly to IEEE 754 `std::fmod(a, b)`.

---

### 3. Edge Cases: Step = 0, Infinities, and Sign Preservation

CSS Values and Units Level 4 §10.4 and §10.10 (Type Checking and NaN/Infinity) strictly follow IEEE 754 semantics with CSS-specific overrides:

1.  **Step / Divisor $B = 0$ ($+0.0$ or $-0.0$):**
    *   `round(*, A, 0)`: Division by zero yields `NaN`.
    *   `mod(A, 0)` and `rem(A, 0)`: Yield `NaN`.
2.  **Infinite Dividend / Value ($A = \pm\infty$):**
    *   `round(*, ±∞, B)`: If $B$ is finite and non-zero, returns $\pm\infty$ (preserving the sign of $A$). If $B = \pm\infty$, returns `NaN`.
    *   `mod(±∞, B)` and `rem(±∞, B)`: Return `NaN` for any $B$.
3.  **Infinite Step / Divisor ($B = \pm\infty$) with Finite $A$:**
    *   **`round(strategy, A, ±∞)`:**
        *   `nearest` or `to-zero`: Returns $+0.0$ if $A \ge +0.0$, and $-0.0$ if $A \le -0.0$.
        *   `up`: If $A > 0$, returns $+\infty$. If $A < 0$, returns $-0.0$. If $A = \pm 0.0$, returns $A$ (sign preserved).
        *   `down`: If $A < 0$, returns $-\infty$. If $A > 0$, returns $+0.0$. If $A = \pm 0.0$, returns $A$.
    *   **`mod(A, ±∞)`:**
        *   If $\text{sign}(A) \neq \text{sign}(B)$ and $A \neq 0$, returns $\pm\infty$ (matching sign of $B$).
        *   If $\text{sign}(A) = \text{sign}(B)$ or $A = \pm 0.0$, returns $A$ (Wait: per spec, if signs match, $\lfloor A / \infty \rfloor = 0$, so $A - \infty \cdot 0 = A$, preserving sign of $A$. However, `mod` requires sign of $B$, so if $A = -0.0$ and $B = +\infty$, result is $+0.0$).
    *   **`rem(A, ±∞)`:** Always returns $A$ (preserving exact value and sign, including $\pm 0.0$).
4.  **Sign of Zero Preservation ($\pm 0.0$):**
    *   When `round(A, B)` rounds a non-zero finite $A$ to $0$, the result is $-0.0$ if $A < 0$ and $+0.0$ if $A > 0$.
    *   When `rem(A, B)` equals $0$, its sign matches $A$ (`std::copysign(0.0, a)`).
    *   When `mod(A, B)` equals $0$, its sign matches $B$ (`std::copysign(0.0, b)`).

---

### 4. Mathematical Invariants (Finite Real Domain $B \neq 0$)

For finite $A, B \in \mathbb{R}$ with $B \neq 0$:
1.  **Step Multiplicity (`round`):** $\forall s \in \text{Strategy}, \exists k \in \mathbb{Z}, \text{round}(s, A, B) = k \cdot B$.
2.  **Step Sign Invariance (`round`):** $\forall s, \text{round}(s, A, B) = \text{round}(s, A, -B) = \text{round}(s, A, |B|)$.
3.  **Bounding Interval (`round`):** $|A - \text{round}(s, A, B)| < |B|$ for `up`, `down`, `to-zero`, and $|A - \text{round}(\text{nearest}, A, B)| \le \frac{|B|}{2}$.
4.  **Sign of `mod`:** $\text{mod}(A, B) = 0 \lor \text{sgn}(\text{mod}(A, B)) = \text{sgn}(B)$, with $0 \le |\text{mod}(A, B)| < |B|$.
5.  **Sign of `rem`:** $\text{rem}(A, B) = 0 \lor \text{sgn}(\text{rem}(A, B)) = \text{sgn}(A)$, with $0 \le |\text{rem}(A, B)| < |B|$.
6.  **Euclidean Division Reconstruction:**
    *   $A = B \cdot \lfloor A / B \rfloor + \text{mod}(A, B)$
    *   $A = B \cdot \text{trunc}(A / B) + \text{rem}(A, B)$
7.  **Determinism:** Evaluation of AST nodes is a pure total function from environment/operands to extended reals.

---

### 5. Formalization in Rocq / Coq (`BlinkCSSSteppedMathSemantics.v`)

The following complete, self-contained Coq specification formalizes both the exact real mathematical invariants (over $\mathbb{R}$ via `Reals`) and the extended IEEE-754/CSS edge-case state machine (handling $\pm 0.0, \pm\infty, \text{NaN}$).

```coq
(** * BlinkCSSSteppedMathSemantics.v
    Formalization of Chromium Blink CSS Values and Units Level 4 §10.4
    Stepped Value Functions: round(), mod(), and rem(). *)

From Coq Require Import Reals ZArith Lra Psatz Bool.
Open Scope R_scope.

(** ** 1. AST and Operator Definitions (Mirroring Blink C++) *)

Inductive RoundingStrategy : Type :=
  | Nearest
  | Up
  | Down
  | ToZero.

Inductive CSSMathOperator : Type :=
  | kRound (s : RoundingStrategy)
  | kMod
  | kRem.

(** ** 2. Floor, Ceil, and Truncate over Reals *)

(** In Coq's Standard Library, [up r] is the archimedean integer such that
    [IZR (up r) - 1 <= r < IZR (up r)]. Thus [floor r = up r - 1]. *)

Definition Rfloor (r : R) : Z := (up r - 1)%Z.
Definition Rceil (r : R) : Z :=
  if Req_EM_T (IZR (Rfloor r)) r then Rfloor r else up r.
Definition Rtrunc (r : R) : Z :=
  if Rlt_dec r 0 then Rceil r else Rfloor r.

Lemma Rfloor_spec : forall r : R, IZR (Rfloor r) <= r < IZR (Rfloor r) + 1.
Proof.
  intro r. unfold Rfloor.
  rewrite minus_IZR.
  destruct (archimed r) as [H1 H2].
  split; lra.
Qed.

Lemma Rceil_spec : forall r : R, IZR (Rceil r) - 1 < r <= IZR (Rceil r).
Proof.
  intro r. unfold Rceil.
  destruct (Req_EM_T (IZR (Rfloor r)) r) as [Heq | Hneq].
  - rewrite Heq. lra.
  - unfold Rfloor in Hneq. rewrite minus_IZR in Hneq.
    destruct (archimed r) as [H1 H2].
    split; lra.
Qed.

Lemma Rtrunc_spec_nonneg : forall r : R, 0 <= r -> Rtrunc r = Rfloor r.
Proof.
  intros r Hr. unfold Rtrunc.
  destruct (Rlt_dec r 0); [lra | reflexivity].
Qed.

Lemma Rtrunc_spec_neg : forall r : R, r < 0 -> Rtrunc r = Rceil r.
Proof.
  intros r Hr. unfold Rtrunc.
  destruct (Rlt_dec r 0); [reflexivity | lra].
Qed.

(** ** 3. Pure Real Semantics (For Finite Non-Zero Step/Divisor) *)

Definition eval_mod_R (a b : R) : R :=
  a - b * IZR (Rfloor (a / b)).

Definition eval_rem_R (a b : R) : R :=
  a - b * IZR (Rtrunc (a / b)).

Definition eval_round_R (s : RoundingStrategy) (a b : R) : R :=
  let step := Rabs b in
  match s with
  | Down    => step * IZR (Rfloor (a / step))
  | Up      => step * IZR (Rceil (a / step))
  | ToZero  => step * IZR (Rtrunc (a / step))
  | Nearest =>
      (** CSS Values 4 §10.4: Ties round towards +infinity