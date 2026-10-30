**AUDIT LOG: AGENT 308**
**SUBSYSTEM:** Chromium Blink Engine (`third_party/blink/renderer/core/animation/`)
**SUBJECT:** Keyframe Timing Delay Calculation and Non-Negativity Enforcement

---

### 1. Architectural Context: Effect Delay vs. Keyframe Offset
In the Blink animation engine (implementing the Web Animations API and CSS Animations/Transitions), timing delays are bifurcated into two distinct mathematical concepts:
1.  **Effect-Level Delay (`start_delay` / `end_delay`):** Handled in `Timing` (`timing.h`) and `AnimationEffect`. These define when the entire animation effect begins and ends relative to the timeline.
2.  **Keyframe-Level Delay (`offset`):** Handled in `Keyframe` (`keyframe.h`) and `KeyframeEffectModelBase` (`keyframe_effect_model.cc`). Individual keyframes do not possess a "delay" property in the specification; rather, their temporal delaying within the active interval is calculated via **fractional offsets** mapped against the `iteration_duration`.

### 2. Delay Calculation Mechanics

#### A. Effect-Level Delay Calculation
Effect delays are represented internally using `AnimationTimeDelta` (typically wrapping `base::TimeDelta`). 
*   **Time-Based Animations:** The delay is parsed directly from CSS (`animation-delay`) or WAAPI (`delay` dictionary member) into seconds/milliseconds.
*   **Timeline-Based (Scroll/View) Animations:** If the delay is phase-based or percentage-based, Blink resolves the delay dynamically against the timeline's range before converting it into an intrinsic `AnimationTimeDelta` equivalent for the local time calculation.

During a timing update (`TimingCalculations`), the **Local Time** (from the `Animation` clock) is converted to **Active Time**. The `start_delay` directly offsets this calculation:
$$\text{Active Time} = \text{Local Time} - \text{Start Delay}$$
*(Assuming the animation is in the active phase and playback rate > 0).*

#### B. Keyframe-Level Offset (Intra-Iteration Delay) Calculation
To determine when a specific keyframe takes effect, Blink normalizes keyframe offsets into the range $[0.0, 1.0]$ via `KeyframeEffectModelBase::GetComputedOffsets()`.

1.  **Explicit Offsets:** Keyframes with defined offsets retain their values.
2.  **Implicit Offsets:** Keyframes with `null` offsets are spaced evenly between adjacent keyframes that possess explicit offsets. If the first keyframe is `null`, it defaults to `0.0`. If the last is `null`, it defaults to `1.0`.
3.  **Temporal Mapping:** During `EnsureKeyframeGroups()`, the engine maps the normalized offset to an actual time delay within the iteration by comparing it against the **Transformed Progress** (which accounts for `iteration_duration` and effect-level easing).

The effective time delay ($T_k$) of a specific keyframe ($k$) from the start of an iteration is:
$$T_k = \text{ComputedOffset}_k \times \text{IterationDuration}$$

*(Note: If keyframe-specific `easing` is applied, it does not alter $T_k$. Instead, it alters the interpolation curve between $T_k$ and $T_{k+1}$).*

---

### 3. Non-Negativity Enforcement & Constraints

Agent 308's audit of the non-negativity constraints reveals strict boundary separation between delays, offsets, and durations within Blink's validator logic (`TimingInput` and `CSSParsingUtils`).

#### A. Keyframe Offsets: Strict Non-Negativity
**Status: ENFORCED.**
Within a standard `KeyframeEffect`, individual keyframe offsets **cannot be negative**.
*   **Domain Constraint:** $\text{Offset} \in [0.0, 1.0]$.
*   **Blink Enforcement:** In `KeyframeEffectModelBase` and `EffectInput::ConvertKeyframes`, any keyframe offset evaluated at $< 0.0$ or $> 1.0$ triggers a `DOMException` (`TypeError` in WAAPI) or causes the CSS rule to be ignored as invalid at parse time. 
*   **Monotonicity:** Offsets must also be monotonically non-decreasing ($O_k \le O_{k+1}$). Blink enforces this strictly; out-of-order keyframes in WAAPI throw a `TypeError`, while CSS keyframes are stably sorted by offset prior to model construction.

#### B. Iteration Duration: Strict Non-Negativity
**Status: ENFORCED.**
Because keyframe delays are multipliers of the `iteration_duration`, the duration itself must be non-negative to prevent inverted keyframe timelines.
*   **Blink Enforcement:** Validated via `DCHECK_GE(iteration_duration, AnimationTimeDelta())` in `timing.h`. Negative durations supplied to WAAPI throw a `TypeError`. CSS negative `animation-duration` values fail parsing.

#### C. Effect-Level `start_delay`: Permitted Negativity (With Clamping)
**Status: EXEMPT (Negative values permitted by spec, clamped at calculation).**
While keyframe offsets must be non-negative, the effect-level `start_delay` **can** be negative. 
*   **Effect of Negative Delay:** A negative `start_delay` causes the animation to begin immediately, but skips forward into the active interval as if it had started in the past. 
*   **Impact on Keyframes:** If `start_delay` is $-2\text{s}$ and `iteration_duration` is $4\text{s}$, the animation immediately initializes at a progress of $0.5$. Consequently, all keyframes with offsets $< 0.5$ are bypassed on the initial frame.
*   **Active Time Non-Negativity:** Despite allowing a negative `start_delay`, the resulting **Active Time** passed to the keyframe interpolation engine is strictly **non-negative**. In `CalculateActiveTime()`, if $(\text{Local Time} - \text{Start Delay}) < 0$ (and `fill_mode` does not dictate otherwise), the engine returns `nullopt` (unresolved), preventing negative time values from ever reaching the keyframe offset interpolator.

### 4. Audit Summary
Blink maintains mathematical integrity during keyframe timing resolution by isolating negative time shifts to the `AnimationEffect` boundary (`start_delay`). By the time execution reaches `KeyframeEffectModelBase` for property interpolation, both the `IterationDuration` and the `TransformedProgress` (and by extension, all keyframe offset delays) are guaranteed to be **strictly non-negative**. 

**AUDIT STATUS:** COMPLIANT. End of log.