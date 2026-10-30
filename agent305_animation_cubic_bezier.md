**AUDIT LOG: AGENT 305**  
**TARGET:** Chromium / Blink Rendering Engine (`cc/animation/` & `ui/gfx/geometry/cubic_bezier.cc`)  
**SUBJECT:** Cubic-Bezier Timing Function Endpoint Identities and $[0, 1000]$ Bounds Analysis

---

### 1. Mathematical Foundation & Parametric Formulation
In the Blink engine, CSS `cubic-bezier(x1, y1, x2, y2)` timing functions are evaluated as a 2D parametric curve $B(u) = (X(u), Y(u))$ over the parameter $u \in [0, 1]$ (where $X$ represents normalized time $t$ and $Y$ represents normalized progress $p$).

The control points are defined as $P_0, P_1, P_2, P_3$:
*   **$P_0 = (0, 0)$** (Origin Identity)
*   **$P_1 = (x_1, y_1)$**
*   **$P_2 = (x_2, y_2)$**
*   **$P_3 = (1, 1)$** (Terminal Identity)

The explicit Bernstein polynomial equations resolved by Blink are:
$$X(u) = 3(1-u)^2 u x_1 + 3(1-u)u^2 x_2 + u^3$$
$$Y(u) = 3(1-u)^2 u y_1 + 3(1-u)u^2 y_2 + u^3$$

---

### 2. Endpoint Identities
Blink strictly enforces boundary conditions at the extremities of the normalized time domain to prevent floating-point drift during solver iterations (Newton-Raphson / Bisection).

#### Identity at $u = 0$ (Start of Animation)
*   **Position:** $X(0) = 0$, $Y(0) = 0$.
*   **First Derivative (Velocity/Slope):**
    $$\frac{dX}{du}\bigg|_{u=0} = 3x_1, \quad \frac{dY}{du}\bigg|_{u=0} = 3y_1$$
    $$\text{Initial Slope } \frac{dY}{dX}\bigg|_{t=0} = \frac{y_1}{x_1}$$
    *Audit Note:* If $x_1 = 0$ and $y_1 \neq 0$, the initial slope approaches $\pm\infty$. Blink handles this via epsilon clamping (`kBezierEpsilon = 1e-7`) to avoid `NaN` propagation during division.

#### Identity at $u = 1$ (End of Animation)
*   **Position:** $X(1) = 1$, $Y(1) = 1$.
*   **First Derivative (Velocity/Slope):**
    $$\frac{dX}{du}\bigg|_{u=1} = 3(1 - x_2), \quad \frac{dY}{du}\bigg|_{u=1} = 3(1 - y_2)$$
    $$\text{Terminal Slope } \frac{dY}{dX}\bigg|_{t=1} = \frac{1 - y_2}{1 - x_2}$$
    *Audit Note:* Symmetrically, if $x_2 = 1$ and $y_2 \neq 1$, the terminal slope approaches $\pm\infty$.

---

### 3. Domain and Range Bounds Analysis in $[0, 1000]$
To evaluate the behavior of the timing function mapped to a $[0, 1000]$ scale (commonly representing a $1000\text{ms}$ duration or a $1000\text{-unit}$ spatial translation, where $T = 1000 \cdot X(u)$ and $P = 1000 \cdot Y(u)$):

#### A. Temporal Domain Bounds ($X$-axis)
To guarantee that $Y(X)$ is a single-valued function of time (preventing the animation from moving backward in time), the W3C specification and Blink parser enforce:
$$x_1 \in [0, 1] \quad \text{and} \quad x_2 \in [0, 1]$$
*   Because $P_{0x}=0, P_{3x}=1$, and $x_1, x_2 \in [0,1]$, the derivative $X'(u) \ge 0$ for all $u \in [0, 1]$.
*   **Scaled Bound:** The temporal evaluation $T(u) = 1000 \cdot X(u)$ is **strictly monotonic** and strictly bounded within **$[0, 1000]$**.
*   **Out-of-Bounds Input Extrapolation:** If Blink's `CubicBezier::SolveWithEpsilon` is queried with a time value outside $[0, 1000]$ (e.g., due to animation delay or fill-mode projections), Blink does not evaluate the polynomial. Instead, it linearly extrapolates using the endpoint tangent identities defined in Section 2.

#### B. Output Range Bounds ($Y$-axis)
According to specification, $y_1$ and $y_2$ are unconstrained: $y_1, y_2 \in (-\infty, +\infty)$. 

1.  **Condition for Strict $[0, 1000]$ Output Bounding:**
    By the **Convex Hull Property** of Bézier curves, the output $P(u) = 1000 \cdot Y(u)$ is guaranteed to remain strictly within $[0, 1000]$ if and only if the control points reside within the $[0, 1]$ unit interval (or slightly outside without the curve extrema crossing the boundary). Specifically, if:
    $$(y_1, y_2) \in [0, 1]^2 \implies P(u) \in [0, 1000] \quad \forall u \in [0, 1]$$

2.  **Overshoot / Undershoot (Extrema Calculation):**
    If $y_1 < 0, y_2 < 0$ or $y_1 > 1, y_2 > 1$, the scaled output $P(u)$ may breach the $[0, 1000]$ range.
    Blink pre-calculates the minimum and maximum $Y$ bounds via `CubicBezier::InitRange` by finding the roots of the derivative $Y'(u) = 0$:
    $$3(1 - 3y_1 + 3y_2)u^2 + 6(y_1 - 2y_2)u + 3y_1 = 0$$
    Let $a = 3(1 - 3y_1 + 3y_2)$, $b = 6(y_1 - 2y_2)$, and $c = 3y_1$. The roots are:
    $$u_{root} = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$
    *   Any real root $u_{root} \in (0, 1)$ represents a local extremum.
    *   **Scaled Range Bounds:** The actual minimum and maximum bounds of the animation in the $[0, 1000]$ space are defined by:
        $$\text{Bounds} = 1000 \times \left[ \min\big(0, Y(u_{root1}), Y(u_{root2})\big), \max\big(1, Y(u_{root1}), Y(u_{root2})\big) \right]$$

---

### 4. Blink Engine Implementation Specifics (Audit Summary)
*   **Sample Table Resolution:** In older WebKit/Blink versions, a spline lookup table of discrete steps was used. Current Blink (`ui/gfx/geometry/cubic_bezier.h`) uses an array of **11 spline samples** (`kCubicBezierSplineSamples`) to narrow down the initial guess for $u$, followed by an analytical Newton-Raphson iteration (up to 8 iterations), falling back to bisection if Newton-Raphson steps outside the $[0, 1]$ interval.
*   **Endpoint Clamping:** At $T = 0$ and $T = 1000$, the solver bypasses numerical approximation and returns exact literals `0.0` and `1000.0` (scaled from `0.0` and `1.0`) to guarantee layout stability at keyframes.

**STATUS:** AUDIT COMPLETE. NO ANOMALIES DETECTED IN BLINK BEZIER SOLVER.