### 1. Core Data Structures in Blink Media Queries

In Chromium’s Blink rendering engine (primarily located within `third_party/blink/renderer/core/css/`), CSS Media Queries Level 4 §2.4.3 (Media Feature Range Contexts) are represented and evaluated through a dedicated hierarchy of AST nodes and an evaluation engine.

#### `MediaQueryOperator`
Defined within `media_query_exp.h`, this enumeration represents the relational operators permitted by the Level 4 Range Syntax specification:
* `kNone`: Used for boolean contexts (e.g., `(color)`) or legacy prefix syntax before normalization.
* `kEq`: Represents `=` (equal to).
* `kLt`: Represents `<` (strictly less than).
* `kLe`: Represents `<=` (less than or equal to).
* `kGt`: Represents `>` (strictly greater than).
* `kGe`: Represents `>=` (greater than or equal to).

#### `MediaQueryExpComparison` & `MediaQueryExpBounds`
To unify single comparisons (e.g., `(width <= 600px)`) and double-bounded interval comparisons (e.g., `(400px < width <= 800px)`), Blink structures bounds around the feature identifier:
* `MediaQueryExpValue`: Holds a typed CSS value (e.g., `CSSPrimitiveValue` resolved to a `double` in canonical pixel units, a ratio, an integer, or a CSS identifier).
* `MediaQueryExpComparison`: Couples a `MediaQueryExpValue` with a `MediaQueryOperator`.
  ```cpp
  struct MediaQueryExpComparison {
      MediaQueryExpValue value;
      MediaQueryOperator op = MediaQueryOperator::kNone;
      bool IsValid() const { return value.IsValid(); }
  };
  ```
* `MediaQueryExpBounds`: Represents the range surrounding a media feature name:
  ```cpp
  struct MediaQueryExpBounds {
      MediaQueryExpComparison left;
      MediaQueryExpComparison right;
      bool IsRange() const {
          return left.op != MediaQueryOperator::kNone || right.op != MediaQueryOperator::kNone;
      }
  };
  ```
  *Note on normalization*: Legacy `min-width: 400px` and `max-width: 800px` are normalized or evaluated equivalently to `right` bounds with `kGe` and `kLe` respectively. For a single range expression like `(600px >= width)`, the parser populates `left` with `(600px, kGe)`. For `(width <= 600px)`, the parser populates `right` with `(600px, kLe)`.

#### `MediaQueryExp` & `MediaQueryExpNode`
* `MediaQueryExp`: Associates a media feature string (`media_feature_`, e.g., `media_feature_names::kWidthMediaFeature`) with a `MediaQueryExpBounds` instance.
* `MediaQueryExpNode`: The AST base class for complex queries combining multiple expressions via boolean combinators (`MediaQueryAndExpNode`, `MediaQueryOrExpNode`, `MediaQueryNotExpNode`, `MediaQueryFeatureExpNode`, `MediaQueryUnknownExpNode`).

#### `MediaQueryEvaluator`
Defined in `media_query_evaluator.h/.cc`, this class holds a pointer to a `MediaValues` object (which encapsulates the current viewport state: `ViewportWidth()`, `ViewportHeight()`, `DevicePixelRatio()`, etc.). It traverses the `MediaQueryExpNode` tree, invoking feature-specific evaluation functions (e.g., `WidthMediaFeatureEval`) and returning a three-valued logic state (`KleeneValue`: `kTrue`, `kFalse`, `kUnknown`).

---

### 2. Evaluation Semantics

When `MediaQueryEvaluator::Eval(const MediaQueryExp& expr)` is invoked for a dimensional feature such as `width`:

1. **Viewport Extraction & Canonicalization**:
   The evaluator queries `media_values_->ViewportWidth()`, which returns a `double` representing the layout viewport width in CSS pixels (`px`). Any CSS lengths in `expr.Bounds().left.value` and `expr.Bounds().right.value` are computed against `MediaValues` into canonical CSS pixels (`double`).

2. **Directional Evaluation (`CompareValue`)**:
   Blink defines a polymorphic comparison helper `CompareValue(actual_value, exp_value, op)`. However, special care is taken for `left` vs. `right` bounds because the operator in `left` is written with the bound on the left-hand side of the feature name:

   $$\text{Expression: } (L \;\text{op}_L\; \text{feature} \;\text{op}_R\; R)$$

   * **Right Comparison** ($\text{feature} \;\text{op}_R\; R$):
     The feature value $v$ is on the LHS, and the bound value $R$ is on the RHS.
     $$\text{EvalRight}(v, \text{op}_R, R) = \begin{cases} 
     v = R & \text{if } \text{op}_R = \text{kEq} \\
     v < R & \text{if } \text{op}_R = \text{kLt} \\
     v \le R & \text{if } \text{op}_R = \text{kLe} \\
     v > R & \text{if } \text{op}_R = \text{kGt} \\
     v \ge R & \text{if } \text{op}_R = \text{kGe} \\
     \top & \text{if } \text{op}_R = \text{kNone}
     \end{cases}$$

   * **Left Comparison** ($L \;\text{op}_L\; \text{feature}$):
     Here, the bound $L$ is on the LHS, and the feature value $v$ is on the RHS. In Blink's `CompareDoubleValue`, either the arguments are passed as `(L, v, op_L)` or the operator is inverted:
     $$\text{EvalLeft}(L, \text{op}_L, v) = \begin{cases} 
     L = v & \text{if } \text{op}_L = \text{kEq} \\
     L < v \iff v > L & \text{if } \text{op}_L = \text{kLt} \\
     L \le v \iff v \ge L & \text{if } \text{op}_L = \text{kLe} \\
     L > v \iff v < L & \text{if } \text{op}_L = \text{kGt} \\
     L \ge v \iff v \le L & \text{if } \text{op}_L = \text{kGe} \\
     \top & \text{if } \text{op}_L = \text{kNone}
     \end{cases}$$

3. **Concrete Trace Examples**:
   * **Single Bound `(width <= 600px)`**:
     `left` is `(invalid, kNone)`. `right` is `(600.0, kLe)`.
     Given viewport width $w$:
     $$\text{Eval} = \top \land (w \le 600.0) \iff w \le 600.0$$
   * **Double-Bounded Interval `(400px < width <= 800px)`**:
     The CSS Parser validates that the left and right operators are directionally compatible (both must be `<`/`<=` or both `>`/`>=`; mixing `<` and `>` is a parse error per CSS Media Queries 4 §2.4.3).
     `left` is `(400.0, kLt)`. `right` is `(800.0, kLe)`.
     Given viewport width $w$:
     $$\text{Eval} = \text{EvalLeft}(400.0, \text{kLt}, w) \land \text{EvalRight}(w, \text{kLe}, 800.0) \iff (400.0 < w) \land (w \le 800.0)$$

---

### 3. Interval Containment and Boolean Combination

#### Interval Containment
Every valid `MediaQueryExpBounds` over a 1D continuous domain $\mathbb{D}$ (such as $\mathbb{R}$ or $\mathbb{Z}$) maps directly to a convex interval $I \subseteq \mathbb{D}$:
* `(width <= 600px)` $\mapsto (-\infty, 600]$
* `(400px < width <= 800px)` $\mapsto (400, 800]$
* `(width = 500px)` $\mapsto [500, 500]$
* `(500px < width < 400px)` $\mapsto (500, 400) = \emptyset$ (syntactically valid per CSS MQ4 grammar, evaluates identically to `false` for all $w$).

#### Boolean Combinations (`and`, `or`, `not`)
CSS Media Queries Level 4 §2.2-2.3 specifies **Kleene three-valued logic** ($\{\text{True}, \text{False}, \text{Unknown}\}$) to handle forward-compatible grammar extensions (`<general-enclosed>`). However, for well-formed, supported range queries over known dimensional features, the evaluation image is strictly within classical two-valued Booleans $\mathbb{B} = \{\text{True}, \text{False}\}$.

In `MediaQueryEvaluator::Eval(const MediaQueryExpNode& node)`:
* **Conjunction (`MediaQueryAndExpNode`)**: Evaluates `left` and `right` sub-trees. Over known range queries, this corresponds to set intersection of the solution spaces:
  $$\llbracket Q_1 \text{ and } Q_2 \rrbracket_v = \llbracket Q_1 \rrbracket_v \land \llbracket Q_2 \rrbracket_v \quad \longleftrightarrow \quad v \in (S_{Q_1} \cap S_{Q_2})$$
* **Disjunction (`MediaQueryOrExpNode`)**: Corresponds to set union of the solution spaces:
  $$\llbracket Q_1 \text{ or } Q_2 \rrbracket_v = \llbracket Q_1 \rrbracket_v \lor \llbracket Q_2 \rrbracket_v \quad \longleftrightarrow \quad v \in (S_{Q_1} \cup S_{Q_2})$$
* **Negation (`MediaQueryNotExpNode`)**: Corresponds to set complement:
  $$\llbracket \text{not } Q \rrbracket_v = \neg \llbracket Q \rrbracket_v \quad \longleftrightarrow \quad v \in (\mathbb{D} \setminus S_Q)$$

---

### 4. Mathematical Invariants

1. **Monotonicity of One-Sided Inequalities**:
   * **Upper-bounded queries** (e.g., $v < R$ or $v \le R$, or $L > v$ or $L \ge v$) are **monotonically non-increasing** (downward closed):
     $$\forall v_1, v_2 \in \mathbb{D},\; v_1 \le v_2 \implies (\text{EvalUpper}(v_2) = \text{ true} \implies \text{EvalUpper}(v_1) = \text{ true})$$
   * **Lower-bounded queries** (e.g., $v > R$ or $v \ge R$, or $L < v$ or $L \le v$) are **monotonically non-decreasing** (upward closed):
     $$\forall v_1, v_2 \in \mathbb{D},\; v_1 \le v_2 \implies (\text{EvalLower}(v_1) = \text{ true} \implies \text{EvalLower}(v_2) = \text{ true})$$

2. **Convexity of `MediaQueryExpBounds`**:
   For any `MediaQueryExpBounds` $B$ whose operators obey the CSS MQ4 grammar restrictions (no `!=` operator), its удовлетворяющее (satisfying) set is convex:
   $$\forall v_1, v_2, v_3 \in \mathbb{D},\; (v_1 \le v_2 \le v_3) \land \text{EvalBounds}(B, v_1) \land \text{EvalBounds}(B, v_3) \implies \text{EvalBounds}(B, v_2)$$

3. **De Morgan's Laws & Operator Duality**:
   * At the boolean AST level (`MediaQueryExpNode`), De Morgan's laws hold both in classical $\mathbb{B}$ and in Kleene 3-valued logic $\mathbb{K}_3$:
     $$\llbracket \text{not } (Q_1 \text{ and } Q_2) \rrbracket_v = \llbracket (\text{not } Q_1) \text{ or } (\text{not } Q_2) \rrbracket_v$$
     $$\llbracket \text{not } (Q_1 \text{ or } Q_2) \rrbracket_v = \llbracket (\text{not } Q_1) \text{ and } (\text{not } Q_2) \rrbracket_v$$
   * At the relational operator level (for strict/non-strict inequalities over a total order), negating a single bound is equivalent to flipping the operator:
     $$\neg (v < R) \iff (v \ge R), \quad \neg (v \le R) \iff (v > R)$$

4. **Determinism**:
   Because `MediaQueryEvaluator` is a pure functional interpreter over an immutable `MediaValues` snapshot and an immutable `MediaQueryExpNode` AST, evaluation is strictly deterministic and referentially transparent.

---

### 5. Rocq / Coq Formalization (`BlinkMediaQueryRangeSemantics.v`)

Below is a complete, self-contained Rocq (Coq) formalization modeling Blink's media query range structures, evaluator, Kleene three-valued logic, interval semantics, and proofs of all required mathematical invariants.

```coq
(** * BlinkMediaQueryRangeSemantics.v
    Formal verification of Chromium Blink's CSS Media Queries Level 4
    Range Syntax Evaluation Engine. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.
Open Scope bool_scope.

(* ========================================================================== *)
(* 1. Core Data Structures (Mirroring Blink's media_query_exp.h)              *)
(* ========================================================================== *)

(** Represents blink::MediaQueryOperator *)
Inductive MediaQueryOperator : Type :=
  | kNone : MediaQueryOperator
  | kEq   : MediaQueryOperator
  | kLt   : MediaQueryOperator
  | kLe   : MediaQueryOperator
  | kGt   : MediaQueryOperator
  | kGe   : MediaQueryOperator.

(** We model canonicalized CSS pixel values in fixed-point / integer units (Z). *)
Definition CSSValue := Z.

(** Represents blink::MediaQueryExpComparison *)
Record MediaQueryExpComparison : Type := mkComparison {
  comp_value : CSSValue;
  comp_op    : MediaQueryOperator
}.

(** Represents blink::MediaQueryExpBounds *)
Record MediaQueryExpBounds : Type := mkBounds {
  bounds_left  : MediaQueryExpComparison;
  bounds_right : MediaQueryExpComparison
}.

(** Represents supported dimensional features in blink::MediaValues *)
Inductive MediaFeature : Type :=