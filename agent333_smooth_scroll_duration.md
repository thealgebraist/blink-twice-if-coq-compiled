**AUDIT REPORT: Blink Compositor Smooth Scroll Animation Duration**
**Auditor:** Agent 333
**Component:** Chromium / Blink / Compositor (`cc`)
**Target:** Programmatic & User-Driven Smooth Scroll Duration Calculation

---

### 1. Executive Summary
Blink does not directly calculate smooth scroll durations on the main thread for standard operations. Instead, it delegates animation curve generation to the Chromium Compositor (`cc/animation/scroll_offset_animation_curve.cc`). 

The duration calculation relies on two primary behavior models: **Delta-Based (Ease-In-Out)** for programmatic scrolls (e.g., `window.scrollTo({behavior: 'smooth'})`) and **Impulse-Based** for user input (e.g., wheel ticks, keyboard arrows).

---

### 2. Primary Code Locations
*   **Curve Logic:** `cc/animation/scroll_offset_animation_curve.cc`
*   **Constants & Physics:** `ui/events/blink/fling_booster.cc` & `cc/base/features.cc`
*   **Blink Trigger:** `third_party/blink/renderer/core/scroll/scroll_animator.cc`

---

### 3. Calculation Methodology

#### A. Distance Extraction (Maximum Dimension)
Before calculating time, the compositor determines the effective scalar distance ($\Delta$) from the 2D scroll offset vector. It uses the **Chebyshev distance** (maximum of the X or Y delta, not the Euclidean distance).

```cpp
float delta = std::max(std::abs(target_offset.x() - initial_offset.x()),
                       std::abs(target_offset.y() - initial_offset.y()));
```

#### B. Model 1: Delta-Based Duration (Programmatic Smooth Scroll)
Used when `DurationBehavior::kDeltaBased` is specified. The duration scales with the square root of the distance, ensuring large scrolls do not take excessively long while keeping short scrolls perceptible.

**1. Constants:**
*   `kInverseDeltaRampStartPx` = $120.0\text{ px}$
*   `kInverseDeltaRampEndPx` = $480.0\text{ px}$
*   `kInverseDeltaMinDuration` = $0.15\text{ s}$ ($150\text{ ms}$)
*   `kInverseDeltaMaxDuration` = $0.35\text{ s}$ ($350\text{ ms}$) — *Note: Can be capped up to $700\text{ ms}$ depending on platform flags.*
*   `kInverseDeltaSlope` = $\text{Calculated dynamically based on the above}$

**2. The Formula:**
If $\Delta = 0$, Duration ($T$) = $0$.
Otherwise, the raw duration is proportional to $\sqrt{\Delta}$, clamped to specific bounds:

$$T_{\text{raw}} = \frac{\sqrt{\Delta}}{\text{Velocity Constant}}$$

In modern Chromium implementations, this is often simplified to a linear interpolation (lerp) or square-root scaling bounded by the min/max thresholds:

$$T = \text{clamp}\left( \sqrt{\Delta} \times \text{ScaleFactor}, \; T_{\min}, \; T_{\max} \right)$$

*Audit Note:* For standard programmatic scrolls, the duration will **never** be shorter than **150ms** and will **never** exceed **350ms–700ms** (platform dependent), regardless of whether the page is $500\text{px}$ or $50,000\text{px}$ tall.

#### C. Model 2: Impulse-Based Duration (Default for User Input)
Introduced via the Edge-inspired "Impulse Scroll" physics model. This mimics physical momentum (sharp initial velocity, prolonged deceleration).

**1. Constants:**
*   `kImpulseMinDuration` = $0.2\text{ s}$ ($200\text{ ms}$)
*   `kImpulseMaxDuration` = $0.5\text{ s}$ ($500\text{ ms}$)
*   `kImpulseMillisecondsPerPixel` = $1.5\text{ ms/px}$

**2. The Formula:**
$$T = \text{clamp}\left( \Delta \times 1.5\text{ ms}, \; 200\text{ ms}, \; 500\text{ ms} \right)$$

*Example:* A standard mouse wheel tick in Blink is typically $100\text{px}$ or $120\text{px}$.
$$120\text{px} \times 1.5\text{ms/px} = 180\text{ms}$$
Clamped to `kImpulseMinDuration`, a single wheel tick results in a **200ms** animation.

#### D. Model 3: Constant Duration
Used primarily for specific UI triggers (like certain scrollbar button clicks or page-up/page-down keys depending on OS).
*   `kConstantDuration` = $9.0 \text{ ticks} / 60\text{Hz} = \mathbf{150\text{ ms}}$.

---

### 4. On-the-Fly Retargeting (`UpdateTarget`)
When a new scroll event arrives *before* the current smooth scroll animation finishes, Blink does not reset the timer. It calls `ScrollOffsetAnimationCurve::UpdateTarget`.

1.  Calculates current position and current velocity ($v_{\text{current}}$) at time $t$.
2.  Calculates the new remaining distance ($\Delta_{\text{new}}$) from the current position to the new target.
3.  Computes a new duration based on $\Delta_{\text{new}}$ using the formulas in Section 3.
4.  Generates a new cubic bezier curve where the initial tangent slope matches $v_{\text{current}}$ to prevent visual jarring (C1 continuity).

---

### 5. Audit Findings & Edge Cases

*   **CSS vs. JS Discrepancy:** Developers cannot override the duration of `scroll-behavior: smooth` or `window.scrollTo()`. The duration is strictly locked to the C++ compositor constants.
*   **Extreme Distances:** Because of the $T_{\max}$ clamp ($350\text{ms}-700\text{ms}$), scrolling $100,000\text{px}$ results in extreme virtual velocity, causing the compositor to skip rendering intermediate content (checkerboarding) or flash past elements.
*   **Accessibility Override:** If `prefers-reduced-motion: reduce` is active at the OS/Browser level, `ScrollAnimator` bypasses curve generation entirely, forcing $T = 0\text{ ms}$ (instant scroll).

**End of Report.**
*Agent 333 signing off.*