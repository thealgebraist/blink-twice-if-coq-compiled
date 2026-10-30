**AUDIT LOG: AGENT 309**  
**SUBJECT:** Blink Animation Engine (`cc/animation` & `third_party/blink/renderer/core/animation`)  
**TOPIC:** Iteration Time Modulo Bounding within `[0, iteration_duration]`  
**STATUS:** ACTIVE AUDIT  

---

### 1. Executive Summary
In the Chromium/Blink rendering engine, calculating the ** Iteration Time** of an animation requires mapping an unbounded or large **Scaled Active Time** into a strictly bounded interval: `[0, iteration_duration]`. 

A naive floating-point modulo (`fmod(scaled_active_time, iteration_duration)`) is insufficient and introduces specification violations—specifically regarding IEEE 754 floating-point inaccuracies and Web Animations API (WAAPI) boundary conditions when animations complete at an exact multiple of the iteration duration.

This audit details the exact mathematical and programmatic bounding mechanisms Blink uses to enforce the `[0, iteration_duration]` invariant.

---

### 2. Prerequisite Definitions
Before modulo bounding is applied, Blink computes the **Scaled Active Time**:
$$\text{Scaled Active Time} = (\text{Active Time} \times |\text{playback\_rate}|) + (\text{iteration\_start} \times \text{iteration\_duration})$$

*   `iteration_duration` ($D$): The duration of a single animation pass. ($D \ge 0$).
*   `iteration_count` ($C$): Number of times the animation repeats ($C \ge 0$, can be $\infty$).
*   `iteration_start` ($S$): The offset into the iteration where the animation begins ($S \ge 0$).

---

### 3. The Modulo Bounding Pipeline

To strictly bound `iteration_time` within $[0, D]$, Blink executes a 4-stage conditional pipeline (primarily within `TimingCalculations` in `core/animation/timing_calculations.h`):

#### Stage A: Zero-Duration Degenerate Case ($D = 0$)
If `iteration_duration` is `0`, a standard modulo operation results in `NaN` (Division by Zero).
*   **Audit Rule:** If $D == 0$, the modulo step is bypassed entirely. `iteration_time` is explicitly clamped to `0`. The interval $[0, 0]$ is satisfied.

#### Stage B: The Terminal Boundary Exception (The Upper Bound `[..., D]`)
 mathematically, $X \pmod D$ yields a half-open interval $[0, D)$. Under standard modulo, `iteration_time` could **never** reach `iteration_duration`, snapping back to `0` at the exact end of an iteration. 

However, WAAPI dictates that if an animation is in the **After Phase** (or at the exact active end boundary) and the total iterations end on an exact integer multiple, the animation must fill at $D$, not $0$.

**Blink's Bounding Logic:**
`iteration_time` is forced to the upper bound `iteration_duration` ($D$) if **all** of the following conditions are met:
1.  **At Active Boundary:** `active_time == active_duration`
2.  **Non-Zero Count:** `iteration_count != 0`
3.  **Integer Alignment:** $(\text{iteration\_start} + \text{iteration\_count}) \pmod 1 == 0$ (Checked within an epsilon tolerance).

If true, modulo is bypassed:
$$\text{iteration\_time} = D$$

#### Stage C: Standard Modulo Operation (`[0, D)`)
If the animation is in the Active Phase (or does not meet the Terminal Boundary conditions), Blink applies the standard floating-point modulo:
$$\text{iteration\_time} = \text{fmod}(\text{scaled\_active\_time}, D)$$

*(Note: Because `scaled_active_time` is guaranteed $\ge 0$ by prior phase-clamping, C++ `std::fmod` will not return negative values, securing the lower bound `0`.)*

#### Stage D: Floating-Point Epsilon Snapping & Clamping
IEEE 754 floating-point arithmetic is notorious for precision drift during `fmod` operations (e.g., `fmod(3.0, 1.0)` might yield `0.99999999999999989` due to time scaling conversions between `base::TimeDelta` and `double`).

Blink enforces a strict post-modulo sanitation pass using `AnimationTimeDelta` and epsilon comparisons (`IsWithinAnimationTimeEpsilon`):

1.  **Upper-Bound Drift Correction:** If $\text{D} - \text{iteration\_time} < \epsilon$:
    *   If at the terminal boundary (Stage B logic), snap to $D$.
    *   Otherwise, wrap around and snap to $0.0$ (since a mid-animation frame shouldn't park on $D$ due to float drift).
2.  **Hard Clamping:** As a final defense against `NaN` or out-of-bounds float representations:
    $$\text{iteration\_time} = \text{std::clamp}(\text{iteration\_time}, 0.0, D)$$

---

### 4. Code-Level Representation (Blink Audit)

Below is the synthesized logic representing Blink's implementation in `third_party/blink/renderer/core/animation/timing_calculations.h`:

```cpp
AnimationTimeDelta CalculateIterationTime(
    AnimationTimeDelta iteration_duration,
    AnimationTimeDelta active_duration,
    AnimationTimeDelta scaled_active_time,
    double start_offset,
    Timing::Phase current_phase,
    const Timing& specified) {

  // Stage A: Zero-Duration Guard
  if (iteration_duration.is_zero())
    return AnimationTimeDelta(); // Returns 0

  // Stage B: Terminal Boundary Exception (Reaching the 'D' in [0, D])
  if ( EndingAtIterationBoundary(specified.iteration_count, specified.iteration_start) &&
       IsAtActiveEnd(scaled_active_time, active_duration, start_offset) ) {
    return iteration_duration;
  }

  // Stage C: Standard Modulo
  AnimationTimeDelta iteration_time = scaled_active_time % iteration_duration;

  // Stage D: Epsilon Correction & Hard Bounding
  if (IsWithinAnimationTimeEpsilon(iteration_time, iteration_duration)) {
    // Prevent float inaccuracy from stalling just shy of 0 wrap-around
    return AnimationTimeDelta(); 
  }

  // Final defensive clamp to guarantee [0, iteration_duration]
  return std::clamp(iteration_time, AnimationTimeDelta(), iteration_duration);
}
```

### 5. Audit Conclusion
Blink successfully bridges the gap between the mathematical half-open modulo $[0, D)$ and the rendering requirement of a closed interval $[0, D]$. By isolating zero-durations, intercepting integer-aligned terminal boundaries before `fmod`, and applying epsilon-snapping afterward, Blink guarantees that downstream interpolation (`CalculateTransformedProgress`) never receives an out-of-bounds `iteration_time`. 

**Agent 309 signing off.**