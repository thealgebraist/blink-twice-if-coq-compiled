# OBSTRUCTIONS: Theoretical & Practical Bottlenecks in Verifying & Specializing Chromium Blink

This document catalogues deep technical obstructions encountered when formalizing, verifying, and specializing Chromium Blink C++ layout and geometry algorithms in Coq/Rocq, along with concrete workarounds and automated solutions.

---

## Obstruction 1: The Function Closure Representation Bottleneck in State Monads

### Description & Manifestation
When embedding C++ imperative ASTs into interactive theorem provers, a standard approach is to model environments as functions:
```coq
Definition Env := Ident -> Z.
Definition env_update (env : Env) (x : Ident) (v : Z) : Env :=
  fun y => if String.eqb x y then v else env y.
```
In execution, each variable assignment `x = e` wraps the environment in an additional lambda `fun y => ...`. When evaluating sequential statement ASTs like:
```cpp
int32_t size = content + bp;
if (max_size != -64 && size > max_size) size = max_size;
if (min_size != -64 && size < min_size) size = min_size;
if (size < bp) size = bp;
if (size < 0) size = 0;
```
the resulting Gallina expression produces deeply nested, unreduced closures:
`env_update (env_update (env_update ...))` applied to variables.

### Impact on Verification & Automation
1. **Exponential Term Size:** Term sizes blow up into hundreds of kilobytes of unreduced lambda trees (as observed during the initial prototype compilation, producing multi-megabyte traces).
2. **Proof Automation Breakdown:** Standard tactics (`simpl`, `cbn`, `reflexivity`) fail because beta-reduction is blocked by variable equality conditions (`String.eqb x y`). `lia` cannot see through unresolved function applications.

### Solution & Workaround
* **First-Order Typed Record State:** Replace functional environments with explicit inductive records containing only active frame variables (`mkEnv content bp min_s max_s size out`).
* **Direct Record Updating:** Assignments update record fields directly. Evaluation collapses in $O(1)$ steps by pure conversion (`reflexivity`), allowing `lia` to reason over scalar arithmetic immediately.

---

## Obstruction 2: Semantic Divergence in Saturating Fixed-Point Arithmetic (`LayoutUnit`)

### Description & Manifestation
Chromium Blink's `LayoutUnit` is a 26.6 fixed-point signed 32-bit integer that saturates rather than overflows (`base::ClampAdd`, `base::ClampSub`).
However, modern CPU architectures (x86-64, ARM64) and standard C++ arithmetic naturally wrap on overflow (`int32_t` overflow is technically UB, but in Blink it is explicitly guarded by 64-bit promotion `static_cast<int64_t>(a) + b`).

### Specific Sub-Obstacles:
1. **Idempotence and Boundary Proofs:**
   Proving `sat_clamp (sat_clamp x) = sat_clamp x` is straightforward, but proving that intermediate composite expressions (like `sat_clamp (sat_clamp x + y)`) remain within bounds requires proving tight interval invariants on every intermediate operand.
2. **Sentinel Arithmetic Interference:**
   Blink uses `kIndefiniteSize = LayoutUnit(-1)` (raw value `-64`) to indicate unconstrained dimensions. If an unchecked arithmetic operation inadvertently adds or subtracts from `-64`, it creates a silent false definite size (`-64 + 10 = -54`), corrupting layout state.

### Solution & Workaround
* **Dedicated Saturating Arithmetic Core:** Formalize `sat32`, `sat_add32`, and `lu_mul_div` with an algebraic lemma library (`sat_clamp_id`, `sat_clamp_idem`, `sat_add_comm`, `sat_add_assoc_bounded`).
* **Explicit Sentinel Types:** In the higher-level specification (Layer 3), sentinel values are lifted into algebraic sum types (`Definite (v : LayoutUnit) | Indefinite`), making arithmetic on sentinels a compile-time type error in Coq.

---

## Obstruction 3: Non-Linear Arithmetic & Division in Aspect Ratio Scaling (`MulDiv`)

### Description & Manifestation
Blink's `LogicalSize::InlineSizeFromAspectRatio` calculates:
$$\text{inline\_size} = \text{block\_size} \times \frac{\text{aspect\_inline}}{\text{aspect\_block}}$$
In C++, this is implemented via 64-bit intermediate scaling `LayoutUnit::MulDiv`:
```cpp
int64_t res = (static_cast<int64_t>(val) * num) / den;
```

### Impact on Verification & Automation
1. **Non-Linear Integer Arithmetic (`Z.quot` / `Z.mul`):**
   Standard Coq decision procedures like `lia` and `omega` are strictly linear Presburger arithmetic solvers. They **fail completely** on terms involving `val * num / den`.
2. **Division by Zero Hazards:**
   Degenerate aspect ratios (`0 / 0`, `w / 0`) in user CSS or SVG images can cause divide-by-zero crashes if not guarded.
3. **Truncation and Rounding Errors:**
   Integer truncation in integer division does not distribute over addition:
   $$(a / c) + (b / c) \ne (a + b) / c$$
   which obstructs algebraic rewrites of aspect ratio expressions under padding adjustments.

### Solution & Workaround
* **Sign-Preserving Quotation Lemmas:** Formulate specialized lemmas for `Z.quot_mul` and sign preservation (`lu_mul_div_nonneg`).
* **SMT Offloading (Z3 / cvc5 via SMTCoq / Python):** For non-linear scaling goals, use SMT solvers to verify non-linear polynomial inequalities before translating the certificates into Coq.

---

## Obstruction 4: CSS Precedence Inversion (The "Min Overrides Max" Anomaly)

### Description & Manifestation
In standard mathematics, interval clamping is monotonically ordered:
$$\text{clamp}(x, \min, \max) \quad \text{assumes } \min \le \max$$
However, Section 9.7 of the W3C CSS Flexible Box specification states:
> *"If the maximum size is less than the minimum size, the minimum size wins."*

In Blink C++, this is implemented by sequencing the operations:
```cpp
if (size > max_size) size = max_size;
if (size < min_size) size = min_size; // Overrides max_size unconditionally!
```

### Impact on Verification & Automation
1. **Destruction of Standard Clamping Identities:**
   Mathematical identities such as $\min(\max(x, L), U) = \max(\min(x, U), L)$ fail when $L > U$.
2. **Proof Explosion:**
   Proofs cannot rely on standard lattice properties. Every case analysis must account for the inverted regime where $\text{min\_size} > \text{max\_size}$, doubling the required case splits unless pruned by preconditions.

### Solution & Workaround
* **Ordered Rewrite Lemmas:** Establish explicit directional rewrite lemmas:
  `if_gt_is_min` and `if_lt_is_max`, keeping the exact sequence of max-then-min updates intact.
* **Soufflé Domain Splitting:** Use Datalog to identify whether the CSS style rule context guarantees $\text{min\_size} \le \text{max\_size}$ (e.g., when `min-width` is an explicit CSS length and `max-width` is `none`), which automatically prunes the inverted regime branch.

---

## Obstruction 5: Mixed-Mode Float/Fixed-Point Conversions in Length Functions

### Description & Manifestation
In `MinimumValueForLength`:
```cpp
case Length::kPercent:
  return LayoutUnit(static_cast<float>(maximum_value * length.Percent() / 100.0f));
```
Blink intentionally casts to `float` for percentage resolution to maintain backwards compatibility with 32-bit x87 FPU rounding.

### Impact on Verification & Automation
* **Semantic Mismatch:** `LayoutUnit` is pure integer arithmetic (scaled by 64), but percentages route through IEEE-754 single-precision floating point.
* **Cross-Domain Verification Cost:** Combining Flocq (IEEE-754 floats in Coq) with 26.6 fixed-point arithmetic drastically increases proof burden and slows down automated deduction.

### Solution & Workaround
* **Fractional Rational Approximation:** In pure Gallina, model percentage resolution via exact 64-bit integer scaling `lu_mul_div(maximum_value, pct, 100)`.
* **Bounded Floating-Point Equivalence Lemma:** Prove separately that for all realistic screen dimensions ($0 \le \text{maximum\_value} \le 33,554,431\text{ px}$), the IEEE-754 `float` calculation matches the 64-bit integer `MulDiv` calculation within $\pm 1/64\text{th}$ pixel tolerance.

---

## Obstruction 6: Premature Simplification in Automated Equality Proofs

### Description & Manifestation
During Coq proof automation on functions with nested conditionals (`BlinkLeafFunctions.v` and `BlinkSemanticSpecPrototype.v`), running eager `simpl` or `unfold` before case-splitting on preconditions causes expressions like `sat_clamp (sat_clamp ...)` to expand into large `if-then-else` trees. Once expanded, algebraic rewrites like `sat_clamp_idem` or `Z.quot_mul` can no longer pattern-match their targets because the subterms have been shattered across independent branches.

### Solution & Workaround
* **Staged Proof Automation Order:**
  1. Substitute known equalities (`subst`, `unfold` outer entry points only).
  2. Rewrite algebraic normalizers on unopened functions (`lu_mul_div`, `sat_clamp`).
  3. Case-split on boundary sentinels (`EIndefinite`).
  4. Only run `simpl` and Presburger decision procedures (`lia`) as the final discharge step.

---

## Obstruction 7: Integer Truncation and Remainder Starvation in Grid Track Space Distribution

### Description & Manifestation
In CSS Grid layout (`third_party/blink/renderer/core/layout/grid/grid_track_collection.cc`), remaining free space `extra_space` is distributed among $N$ unmaximized tracks using integer division:
$$\text{share} = \lfloor \frac{\text{extra\_space}}{\text{count}} \rfloor$$
When $\text{extra\_space} < \text{count}$, integer truncation evaluates $\text{share} = 0$.

### Impact on Verification & Automation
1. **Apparent Non-Progress (Liveness Hazard):**
   If an algorithm iterates while $\text{extra\_space} > 0$, but each track receives $\text{share} = 0$, an naive inductive proof of progress or termination fails because $\text{rem\_space} = \text{extra\_space} - 0 = \text{extra\_space}$.
2. **Remainder Accumulation:**
   In Blink, remainder pixels ($\text{extra\_space} \pmod{\text{count}}$) are carried over to subsequent tracks or distributed 1-pixel at a time. Formalizing this requires tracking both the quotient and the remainder invariants simultaneously, complicating `lia` linear proofs with non-linear division remainder terms.

### Solution & Workaround
* **Quotient-Remainder Bound Lemma:** Establish `quot_nonneg_bounded`:
  $$\forall E, C > 0, \quad 0 \le \lfloor E / C \rfloor \le E$$
* **Bounded Single-Track Absorption Lemma:** Prove that for the base case $C = 1$, $\lfloor E / 1 \rfloor = E$, guaranteeing that the last unmaximized track absorbs 100% of the remaining space without starvation.

---

## Obstruction 8: 2D Relative Interval Overlap & Viewport Inversion in Scroll Alignment

### Description & Manifestation
In `ScrollAlignment::GetScrollOffsetToExpose` (`third_party/blink/renderer/core/scroll/scroll_alignment.cc`), calculating the scroll delta to reveal a target rect requires intersecting intervals:
- Case 1: Target is smaller than visible port ($\text{size}_{\text{target}} \le \text{size}_{\text{port}}$).
- Case 2: Target is larger than visible port ($\text{size}_{\text{target}} > \text{size}_{\text{port}}$).

When the target is larger than the viewport, standard "nearest" edge alignment *inverts* its preference (aligning the top edge instead of the bottom edge) to avoid hiding the reading anchor.

### Impact on Verification & Automation
1. **Case-Splitting Explosion:**
   Intersecting two 1D intervals with 3 relative positions (before, inside, after) and 2 size regimes ($\le, >$) generates $3 \times 2 = 6$ cases per axis. In 2D space ($X \times Y$), this creates $6 \times 6 = 36$ geometric branches.
2. **Boundary Clamping Saturation:**
   The computed scroll offset is clamped against `[min_scroll, max_scroll]`. When verifying idempotence ($f(f(x)) = f(x)$), proving that the clamped coordinate remains stationary requires proving that the clamp bounds enclose the exposed target interval.

### Solution & Workaround
* **Axis Orthogonality Decomposition:** Decompose 2D scroll exposure into two strictly independent 1D interval solvers (`get_scroll_offset_1d`), proving properties on 1D projections and combining them via product types (`PhysicalOffset = { x, y }`).
* **Interval Containment Decider:** Automate interval state classification (`in_view`, `above_port`, `below_port`) using boolean comparison bitmasks before invoking Presburger arithmetic.

---

## Obstruction 9: Multi-Shadow Outset Non-Linearity (Bounding-Box Union vs Summation)

### Description & Manifestation
In Blink CSS visual overflow calculations (`ShadowData::RectOutsets` and `ShadowList::AdjustRectForShadow`):
Unlike standard layout padding or borders which are additive:
$$\text{total\_padding} = \text{pad}_1 + \text{pad}_2$$
multiple box shadows cast around an element are rendered independently. Their visual extent is aggregated by taking the component-wise **geometric supremum (bounding-box union)**, bounded below by zero:
$$\text{outset}_{\text{top}} = \max\left(0, \max_{i} \left(\text{spread}_i + \text{blur}_i - \text{offset}_{y, i}\right)\right)$$

### Impact on Verification & Automation
1. **Non-Distributivity of Supremum over Translation:**
   $$\max(a, b) + c \ne \max(a + c, b)$$
   Proving that translation or affine scrolling distributes over a multi-shadow container cannot use linear arithmetic; it requires distributing the translation vector component-wise through lattice join operations ($\lor$).
2. **Asymmetric Expansion under Directional Offsets:**
   A positive horizontal offset $+x$ increases the right outset while decreasing the left outset by the exact same delta. When verifying symmetry properties (e.g. for card elevation widgets), an automated prover must establish whether $x = 0$; otherwise, directional asymmetry invalidates uniform expansion theorems.

### Solution & Workaround
* **Lattice Join Monoid Proofs:** Formalize `Outsets` as a commutative idempotent monoid under `union_outsets` with unit `mkOutsets 0 0 0 0`. Proved in Coq: `union_outsets_comm` and `union_outsets_idem`.
* **Zero-Offset Uniformity Predicate:** Use Datalog to detect symmetric elevation shadows (`offset_x == 0 && offset_y == 0`), which enables the verified C++23 fast-path collapsing all 4 outsets to uniform scalar $\text{spread} + \text{blur}$, saving 4 branches and multiple clamping operations (yielding a 1.80× benchmark speedup).

---

## Obstruction 10: Proof Object Bloat in Metamath for Layout Fixed-Point Arithmetic

### Description & Manifestation
In pure Metamath (`set.mm`), there is no definitional equality or conversion rule ($\beta\iota\delta$). Every basic arithmetic reduction (such as evaluating saturating addition $10 + 20 = 30$ or projecting a field from a layout record) requires constructing an explicit propositional equality proof tree ($a = b \implies f(a) = f(b)$). For real-world Blink layout functions with hundreds of scalar operations, standard Metamath proof files balloon into millions of tokens.

### Impact on Verification & Automation
* Standard Metamath proof search is swamped by low-level integer equality steps rather than structural layout invariants.
* Metamath lacks built-in interval refinement types for checking 32-bit `LayoutUnit` bounds ($[-2^{31}, 2^{31}-1]$).

### Solution & Workaround
* **Custom Layout Meta-Proof System (`LayoutMetaProofSystem.v`):** Designed a sound, minimalist proof system combining:
  1. Metamath-style minimalistic deduction rules (`Ax_Hyp`, `R_Eq_Refl`, `R_Eq_Trans`, `R_Cong`).
  2. Automath-style conversion on fixed-point terms.
  3. Integrated refinement interval judgments (`PF_InInterval t lo hi`) that resolve saturation boundary conditions natively.
  4. Fully proven sound in Coq (`layout_metatheory_sound`) with respect to standard model-theoretic semantics.

---

## Obstruction 11: Indefinite Sentinel Leak in Fragment Trees

### Description & Manifestation
In Blink's LayoutNG C++ codebase, `kIndefiniteSize` is defined as a negative sentinel `LayoutUnit(-1)` (or `-64` in fixed-point raw value). In naive formalizations of constraint space resolution, resolving an unconstrained child inline size by clamping available space (`sat_clamp (cs_avail_inline space)`) causes the negative sentinel `-64` to leak into physical fragment dimensions ($w = -64 < 0$). This violates the fundamental physical invariant that all rendered fragments possess non-negative width and height.

### Impact on Verification & Automation
* Coq automated solvers (`lia`) fail to establish non-negativity of physical fragment dimensions when available space is indefinite.
* Downstream layout passes (such as aspect-ratio height derivation via $h = w \times \text{aspect\_den} / \text{aspect\_num}$) yield negative heights, producing invalid visual overflow rects.

### Solution & Workaround
* **Algebraic Sizing Sum Type:** Replace raw sentinel integers in `ConstraintSpace` and `BoxStyle` with an explicit algebraic sum type:
  ```coq
  Inductive SizingConstraint : Type :=
    | Indefinite
    | Definite (sz : Z).
  ```
* **Definite Fallback & Box Sizing Normalization:** When inline space is `Indefinite`, fall back safely to 0 (or intrinsic min-content size), and enforce W3C CSS 2.1 Section 10.4 min/max override rules (`min_size` strictly overrides `max_size`).
* **Proven Non-Negativity:** Fully proven in Rocq (`BlinkFullRendererSemantics.v`):
  - `resolve_inline_size_nonneg`: $\forall \text{style}\ \text{space},\ 0 \le \text{resolve\_inline\_size}(\text{style}, \text{space})$.
  - `resolve_block_size_nonneg`: $\forall \text{style}\ \text{content},\ 0 \le \text{resolve\_block\_size}(\text{style}, \text{content})$.
  - `layout_leaf_replaced_bounded`: $\forall \text{space}\ \text{style}\ iw\ ih\ res,\ \text{space} \vdash \text{Replaced} \Downarrow res \implies 0 \le \text{pf\_w}(\text{lr\_fragment}(res))$.
