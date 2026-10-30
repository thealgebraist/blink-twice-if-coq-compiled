**AUDIT REPORT: Blink `ViewTimeline` Crossing Progress Monotonicity**
**Auditor:** Agent 326
**Component:** `third_party/blink/renderer/core/animation/view_timeline.cc` & `cc/animation/scroll_timeline.cc`
**Subject:** Monotonicity Verification Across Named Timeline Ranges (`cover`, `contain`, `entry`, `exit`, `entry-crossing`, `exit-crossing`)

---

### 1. Executive Summary
An audit of the Blink `ViewTimeline` implementation confirms that animation progress ($p$) is **strictly monotonic** with respect to scroll offset ($s$) within any single valid timeline range, provided layout geometry remains static. However, **inversion anomalies (non-monotonic reversals)** can occur in specific edge cases involving dynamic `contain` ranges when target elements equal the scrollport size, or when `view-timeline-inset` evaluations result in negative range distances.

---

### 2. Mathematical Baseline
For any given timeline range, Blink calculates raw progress using the linear interpolation formula:

$$p(s) = \frac{s - s_{\text{start}}}{s_{\text{end}} - s_{\text{start}}}$$

For $p(s)$ to be strictly monotonically increasing with respect to a monotonically increasing scroll offset $s$:
$$\frac{dp}{ds} = \frac{1}{s_{\text{end}} - s_{\text{start}}} > 0 \implies s_{\text{end}} > s_{\text{start}}$$

#### Geometry Definitions:
*   $V$: Scrollport size (height/width depending on axis).
*   $T$: Target element size (border-box).
*   $O_t$: Target offset relative to the scroll container origin.
*   $I_{\text{start}}, I_{\text{end}}$: Effective `view-timeline-inset` values.
*   $V_{\text{eff}} = V - I_{\text{start}} - I_{\text{end}}$ (Effective ViewPort).

---

### 3. Monotonicity Analysis by Named Range

#### A. `cover` (0% to 100%)
*   $s_{\text{start}} = O_t - V + I_{\text{end}}$
*   $s_{\text{end}} = O_t + T - I_{\text{start}}$
*   $\Delta s = s_{\text{end}} - s_{\text{start}} = T + V - (I_{\text{start}} + I_{\text{end}}) = T + V_{\text{eff}}$
*   **Audit Finding:** Monotonicity holds if and only if $T + V_{\text{eff}} > 0$. If aggressive positive insets cause $I_{\text{start}} + I_{\text{end}} > T + V$, $\Delta s$ becomes negative, inverting the timeline derivative ($\frac{dp}{ds} < 0$).

#### B. `entry-crossing` and `exit-crossing`
These ranges explicitly track the physical crossing of the principal box edges across the scrollport edges, ignoring the size switching behavior of standard `entry`/`exit`.
*   **`entry-crossing`**:
    *   $s_{\text{start}} = O_t - V + I_{\text{end}}$
    *   $s_{\text{end}} = O_t - V + I_{\text{end}} + T$
    *   $\Delta s = T$
*   **`exit-crossing`**:
    *   $s_{\text{start}} = O_t - I_{\text{start}}$
    *   $s_{\text{end}} = O_t - I_{\text{start}} + T$
    *   $\Delta s = T$
*   **Audit Finding:** **Strictly Monotonic.** Because $\Delta s = T$, and layout box dimensions are non-negative ($T \ge 0$), $s_{\text{end}} \ge s_{\text{start}}$ is guaranteed. Division by zero occurs at $T = 0$, which Blink resolves to a step function (handled in `ScrollTimeline::CalculateOffsets`).

#### C. `contain` (The Critical Inversion Vector)
*   **Standard Definition ($T < V_{\text{eff}}$):**
    *   $s_{\text{start}} = O_t - V + I_{\text{end}} + T$ (Target finishes entering)
    *   $s_{\text{end}} = O_t - I_{\text{start}}$ (Target starts exiting)
    *   $\Delta s = V_{\text{eff}} - T$
*   **Taller-than-Viewport Definition ($T > V_{\text{eff}}$):**
    *   Without adjustment, $T > V_{\text{eff}} \implies \Delta s < 0$, which would invert progress (animation runs backward while scrolling forward).
    *   **Blink Mitigation:** Per CSS Scroll-Driven Animations spec, Blink swaps the start and end alignments for `contain`, `entry`, and `exit` when $T > V_{\text{eff}}$.
    *   Adjusted $\Delta s = |V_{\text{eff}} - T|$.
*   **Audit Finding:** Monotonicity holds statically, **but fails dynamically** if $T$ or $V$ animates across the $T = V_{\text{eff}}$ boundary during scroll, causing an instantaneous phase inversion.

#### D. `entry` and `exit`
Because `entry` and `exit` share boundary points with `contain`, their $\Delta s$ is defined as:
$$\Delta s = \min(T, V_{\text{eff}})$$
*   **Audit Finding:** Monotonicity holds for all $T > 0$ and $V_{\text{eff}} > 0$. If $V_{\text{eff}} < 0$ (via overlapping insets), $\Delta s$ becomes negative, breaking monotonicity.

---

### 4. Composite Timeline Monotonicity (Cross-Range)
When an animation's `animation-range` spans two different named ranges (e.g., `animation-range: entry 50% exit 50%`), Blink normalizes these into offsets of the overarching `cover` range before sending values to the compositor (`cc`).

1.  `entry 50%` maps to $s_1 = s_{\text{entry\_start}} + 0.5 \cdot \min(T, V_{\text{eff}})$
2.  `exit 50%` maps to $s_2 = s_{\text{exit\_start}} + 0.5 \cdot \min(T, V_{\text{eff}})$

Because $s_{\text{entry\_start}} < s_{\text{exit\_start}}$ is invariant (assuming $T > 0, V_{\text{eff}} > 0$), $s_1 < s_2$ is preserved. The compositor interpolates linearly between $[s_1, s_2]$. Monotonicity is preserved.

---

### 5. Identified Edge Cases & Vulnerabilities

As Agent 326, I am flagging three areas in `view_timeline.cc` where monotonicity guarantees degrade:

1.  **Degenerate Singularity ($T = V_{\text{eff}}$ in `contain`):**
    When Target Size equals Effective Viewport Size, $s_{\text{start}} == s_{\text{end}}$. The range collapses to a 0px scroll distance. Progress jumps discontinuously from $0.0 \to 1.0$ at a single scroll offset. While weakly monotonic, $\frac{dp}{ds} = \infty$, causing frame-skipping of all intermediate keyframes unless handled via `AnimationEffect` inclusive/exclusive boundary rules.
2.  **Negative Effective Viewport ($I_{\text{start}} + I_{\text{end}} > V$):**
    If a developer specifies `view-timeline-inset: 60% 60%`, the start and end insets cross each other. $s_{\text{end}}$ becomes less than $s_{\text{start}}$. Blink does **not** clamp or swap `cover` boundaries in this scenario; the animation progress will monotonically *decrease* as scroll offset *increases*.
3.  **Sub-pixel Layout Thrashing (Compositor/Main Thread Desync):**
    `ViewTimeline::CalculateOffsets` uses `double` precision, while layout geometrics (`LayoutBox::Size()`) often snap to `LayoutUnit` (1/64th pixel). When $T \approx V_{\text{eff}}$, zoom scaling or fractional device pixel ratios can cause `entry`/`exit`/`contain` boundary swaps to flicker, resulting in non-monotonic jitter at the boundary frame.

### Status:
**AUDIT COMPLETE.** Forward findings on negative `V_eff` inset inversions to the Blink Animation team for CSSWG spec compliance verification.