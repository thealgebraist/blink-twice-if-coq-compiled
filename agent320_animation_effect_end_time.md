**AUDIT REPORT: Blink Animation Engine – Effect End Time Calculation**
**Auditor:** Agent 320
**Subject:** `AnimationEffect` / `TimingCalculations` (Web Animations API Spec Compliance)
**Focus Areas:** Non-negativity constraints and Delay Addition logic.

---

### 1. Executive Summary
An audit of the Blink animation subsystem (specifically within `third_party/blink/renderer/core/animation/`) was conducted to verify how the **Effect End Time** is computed. The Effect End Time defines the point in local time when an animation effect finishes its active interval, accounting for its start delay, active duration, and end delay. 

Per the W3C Web Animations specification, the formula is heavily reliant on clamping mechanisms (non-negativity) and precise sequential addition of delays.

---

### 2. Delay Addition Logic
To reach the Effect End Time, Blink must first calculate the **Transformed Progress** boundary by summing three temporal components:
1. **Start Delay ($D_{start}$):** Time before the active interval begins.
2. **Active Duration ($D_{active}$):** $\text{Iteration Duration} \times \text{Iteration Count}$.
3. **End Delay ($D_{end}$):** Time after the active interval concludes, primarily used for sequencing effects.

**The Raw Addition Formula:**
$$\text{Raw End Time} = D_{start} + D_{active} + D_{end}$$

**Audit Findings on Addition:**
* **Negative Delays:** Both $D_{start}$ and $D_{end}$ are permitted to be negative. A negative $D_{start}$ causes the animation to begin midway through its active interval. A negative $D_{end}$ pulls the end time inward, potentially truncating the active duration.
* **Infinity Handling:** If $D_{active}$ is `Infinity` (e.g., `iterationCount: Infinity`), the sum naturally resolves to `Infinity`. Blink uses `AnimationTimeDelta::Max()` to represent this state safely without floating-point overflow.

---

### 3. Non-Negativity Constraints (Clamping)
Because delays can be negative, raw addition can yield a negative timestamp. However, in the local time space of an animation effect, the Effect End Time **cannot precede local time zero ($0$)**.

Blink enforces non-negativity at two critical stages:

#### Stage A: Active Duration Non-Negativity
Before delays are even added, the Active Duration is strictly clamped:
$$D_{active} = \max(\text{Iteration Duration} \times \text{Iteration Count}, 0)$$
*Note: Blink validates inputs via `Timing::AssertValid()`, ensuring that iteration duration and counts are inherently $\ge 0$, making $D_{active}$ strictly non-negative.*

#### Stage B: Final End Time Non-Negativity
When negative delays exceed the active duration, the raw sum drops below zero. Blink applies a `std::max` operation against a zero-delta to enforce the specification's floor:

$$\text{Effect End Time} = \max(D_{start} + D_{active} + D_{end}, 0)$$

**Edge Case Verification:**
* **Scenario 1 (Truncated End):** $D_{start} = 0\text{s}$, $D_{active} = 5\text{s}$, $D_{end} = -2\text{s}$. 
  * *Calculation:* $\max(0 + 5 - 2, 0) = 3\text{s}$. The animation cuts off at 3 seconds.
* **Scenario 2 (Total Eclipse):** $D_{start} = -3\text{s}$, $D_{active} = 2\text{s}$, $D_{end} = -1\text{s}$.
  * *Calculation:* $\max(-3 + 2 - 1, 0) = \max(-2, 0) = 0\text{s}$. 
  * *Result:* The animation's active phase is entirely skipped; it immediately enters the "after" phase at local time $0$.

---

### 4. Blink Implementation Reference
In the Chromium source, this logic is encapsulated within `TimingCalculations` (typically found in `timing_calculations.h`):

```cpp
// Conceptual representation of Blink's internal calculation
AnimationTimeDelta CalculateEndTime(const Timing& specified, 
                                    AnimationTimeDelta active_duration) {
  // 1. Ensure active_duration is non-negative (Guaranteed by caller/assertions)
  DCHECK_GE(active_duration, AnimationTimeDelta());

  // 2. Handle infinite active duration
  if (active_duration.is_max())
    return AnimationTimeDelta::Max();

  // 3. Delay Addition
  AnimationTimeDelta end_time = specified.start_delay.AsTimeDelta() + 
                                active_duration + 
                                specified.end_delay.AsTimeDelta();

  // 4. Non-Negativity Enforcement
  return std::max(AnimationTimeDelta(), end_time);
}
```

### 5. Verdict
**STATUS: COMPLIANT.** 
Blink's use of `AnimationTimeDelta` prevents floating-point underflow during delay addition, and the terminal `std::max(0, ...)` clamp strictly enforces the W3C non-negativity mandate for Effect End Time. **Agent 320 signing off.**