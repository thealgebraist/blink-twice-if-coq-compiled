**AUDIT REPORT: Blink Animation Engine – `StepsTimingFunction`**
**Auditor:** Agent 306
**Target:** `blink::StepsTimingFunction::Evaluate(double fraction, bool before_flag)`
**Objective:** Detail discrete step index bounds and verify mathematical monotonicity in compliance with W3C CSS Easing Functions Level 1.

---

### 1. Mathematical Foundation

In Blink, the `steps(n, <jump-term>)` timing function divides the input domain and output range into $n$ intervals (where $n \ge 1$). 

For a given normalized time progress $t \in (-\infty, \infty)$ and integer step count $n \in \mathbb{Z}^+$, the calculation relies on two intermediate variables:
1. **Current Step Index ($k$):** The discrete index of the time segment.
2. **Output Steps ($m$):** The total number of output divisions, determined by the `StepPosition` enum.

Initially, the raw step index is calculated as:
$$k = \lfloor t \times n \rfloor$$

If the `before_flag` is set (triggered during backwards-filling or at the exact boundary of a discontinuous phase transition) and the fractional remainder $(t \times n) \pmod 1 == 0$, the index is decremented to maintain left-continuity:
$$k \leftarrow k - 1$$

---

### 2. Discrete Step Index Bounds

To prevent floating-point overflow, out-of-bounds phase extrusion, and undefined behavior during CSS delay phases ($t < 0$ or $t > 1$), Blink applies strict clamping to the step index $k$ **only when** $t \in [0, 1]$.

#### A. Unbounded Phase ($t < 0$ or $t > 1$)
* **Index Bounds:** $k \in (-\infty, \infty) \cap \mathbb{Z}$
* **Behavior:** During the active animation phase, $t$ is strictly bounded within $[0.0, 1.0]$. However, when chained inside composite keyframe effects or evaluated outside the active interval, $k$ is initially unconstrained until final clamping is applied based on the jump term.

#### B. Bounded Active Phase ($0.0 \le t \le 1.0$)
Before applying the jump-term transformations, $k$ falls within $[-1, n]$ (accounting for the `before_flag` at $t=0$ and exact arrival at $t=1$). Blink transforms $k$ and sets the denominator $m$ according to the `StepPosition`, clamping the final numerator $k'$ to ensure the output remains strictly within $[0.0, 1.0]$:

| Jump Term (`StepPosition`) | Index Transformation ($k'$) | Denominator ($m$) | Clamped Numerator Bounds ($k'$) | Output Range ($\frac{k'}{m}$) |
| :--- | :--- | :--- | :--- | :--- |
| **`START`** / **`JUMP_START`** | $k + 1$ | $n$ | $[0, n]$ | $[0.0, 1.0]$ |
| **`END`** / **`JUMP_END`** | $k$ | $n$ | $[0, n]$ | $[0.0, 1.0]$ |
| **`JUMP_BOTH`** | $k + 1$ | $n + 1$ | $[0, n + 1]$ | $[0.0, 1.0]$ |
| **`JUMP_NONE`** | $k$ | $n - 1$ *(requires $n > 1$)* | $[0, n - 1]$ | $[0.0, 1.0]$ |

*Audit Note on `JUMP_NONE`:* Blink's CSS parser enforces $n \ge 2$ for `jump-none`. At runtime, a defensive check ensures $m = n - 1$ never evaluates to $0$, preventing `NaN` propagation via division-by-zero.

---

### 3. Monotonicity Analysis

A function $f(t)$ is monotonically non-decreasing if for all $t_1, t_2$ in its domain, $t_1 \le t_2 \implies f(t_1) \le f(t_2)$.

#### A. Global Monotonicity (Fixed `before_flag`)
Holding the `before_flag` constant, the step timing function is a composition of:
1. Linear scaling: $g(t) = t \times n$ (Strictly increasing for $n \ge 1$).
2. The floor function: $h(x) = \lfloor x \rfloor$ (Monotonically non-decreasing).
3. Clamping to $[a, b]$: $\text{clamp}(x, a, b)$ (Monotonically non-decreasing).
4. Positive scalar division: $y / m$ where $m > 0$ (Strictly increasing).

Because the composition of monotonically non-decreasing functions is itself monotonically non-decreasing, **Blink’s `StepsTimingFunction` is globally monotonic** across the entire real domain $\mathbb{R}$.

#### B. Boundary Monotonicity (Variable `before_flag`)
At step boundaries where $t \times n \in \mathbb{Z}$, a discontinuity occurs.
* Let $t_1 = \frac{i}{n}$ evaluated with `before_flag = true`.
* Let $t_2 = \frac{i}{n}$ evaluated with `before_flag = false`.

Even though $t_1 = t_2$, the state transition represents progression in time from the $i\text{-th}$ interval's end to the $(i+1)\text{-th}$ interval's start. 
* For $t_1$, $k_1 = i - 1$.
* For $t_2$, $k_2 = i$.
* Since $k_1 < k_2$, it holds that $f(t_1, \text{true}) \le f(t_2, \text{false})$.

Thus, **temporal monotonicity is preserved across phase transitions**.

#### C. Floating-Point Precision Hazards (Edge-Case Audit)
In C++ (`double` IEEE 754), the product $t \times n$ can suffer from precision loss (e.g., $t = 0.3, n = 10$ yielding $2.9999999999999996$). 
* **Impact on Monotonicity:** None. IEEE 754 multiplication is monotonic. Even if a step boundary shifts by $1 \text{ ULP}$ (Unit in the Last Place), $\lfloor t_1 \times n \rfloor \le \lfloor t_2 \times n \rfloor$ strictly holds for $t_1 < t_2$.
* **Impact on Bounds:** Precision drift at $t = 1.0$ is impossible since $1.0 \times n = n$ is exact for all valid integer steps up to $2^{53}$. The `std::clamp` call acts as a hard barrier against any sub-normal underflows or precision-induced boundary breaches.

---

### 4. Conclusion

**Status: VERIFIED.** 
Blink's implementation of `StepsTimingFunction` maintains strict discrete index bounds via post-transformation clamping and guarantees mathematical and temporal monotonicity across all `StepPosition` configurations.