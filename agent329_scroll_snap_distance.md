**AUDIT LOG: AGENT 329**
**SUBJECT:** Blink Engine (`cc::SnapSelectionStrategy`) Scroll Snap Distance Computation and Non-Negativity Enforcement
**STATUS:** Verified

### 1. Overview of Snap Selection Architecture
In Chromium’s Blink engine, scroll snapping is primarily handled on the compositor thread within the `cc` (Chrome Compositor) namespace to ensure 60/120fps performance. When a scroll event (gesture, wheel, programmatic) terminates or predicts an end position, `cc::SnapContainerData` evaluates potential snap targets (`cc::SnapAreaData`) using a specific `cc::SnapSelectionStrategy`.

There are three primary strategies:
1. **`EndPositionStrategy`**: Snaps based on the natural resting position (e.g., programmatic scroll without momentum).
2. **`DirectionStrategy`**: Snaps based on a directional step (e.g., arrow keys) from the current position.
3. **`EndAndDirectionStrategy`**: Snaps based on both the current position and the predicted fling/momentum end position.

---

### 2. Distance Computation Mechanics

Distance is computed independently along the X and Y axes (1D calculations) except in `scroll-snap-type: both`, where 2D Euclidean distance is occasionally utilized for tie-breaking or simultaneous axis evaluation.

#### A. Base Variables
For a given axis (X or Y):
* $P_{\text{current}}$: The current scroll offset before the snap evaluation.
* $P_{\text{intended}}$: The intended or predicted end scroll offset (incorporating physics/inertial decay).
* $S_{\text{target}}$: The scroll offset required to align the `SnapArea`'s snap-align position with the `SnapContainer`'s snapport.

#### B. 1D Distance Calculation
Depending on the active strategy, the distance $D$ to a candidate snap target is computed as follows:

1. **For `EndPositionStrategy`:**
   The engine measures the distance from the intended resting position to the snap target:
   $$D = |S_{\text{target}} - P_{\text{intended}}|$$

2. **For `DirectionStrategy`:**
   The engine measures the distance from the *current* position to the snap target in the direction of the scroll:
   $$D = |S_{\text{target}} - P_{\text{current}}|$$

3. **For `EndAndDirectionStrategy`:**
   The candidate must first pass a directional filter (must be in the direction of the scroll velocity). If valid, distance is computed relative to the *intended* end position to respect momentum:
   $$D = |S_{\text{target}} - P_{\text{intended}}|$$

#### C. 2D Distance Calculation (`scroll-snap-type: both`)
When evaluating areas that snap in both axes simultaneously, Blink calculates the orthogonal offsets ($\Delta x, \Delta y$) from the intended position:
$$\Delta x = |S_{\text{target}, x} - P_{\text{intended}, x}|$$
$$\Delta y = |S_{\text{target}, y} - P_{\text{intended}, y}|$$
The composite distance is computed via `gfx::Vector2dF::Length()`, which executes standard Euclidean norm:
$$D_{2D} = \sqrt{(\Delta x)^2 + (\Delta y)^2}$$

#### D. Proximity Filtering (`scroll-snap-type: proximity`)
If the container is set to `proximity` rather than `mandatory`, the computed distance $D$ is compared against a threshold (typically a ratio of the snapport size, e.g., $0.3 \times \text{SnapportSize}$). If $D > D_{\text{limit}}$, the candidate is discarded.

---

### 3. Non-Negativity Enforcement

In Blink's scroll snap implementation, **distances are strictly non-negative ($D \ge 0$)** at the point of candidate comparison. Negative distances are structurally impossible during the final minimization phase due to the following mechanisms:

#### A. Directional Culling (Pre-Filter)
Signs (positive or negative displacements) are only used **prior** to distance comparison to validate scroll direction. 
In `DirectionStrategy::IsValidSnapPosition`:
* Let displacement $\vec{v} = S_{\text{target}} - P_{\text{current}}$.
* Let scroll delta be $\vec{\delta}$.
* If $\text{sign}(\vec{v}) \neq \text{sign}(\vec{\delta})$, the candidate is immediately rejected. 

Because candidates in the "wrong" (negative relative to velocity) direction are culled before distance ranking, the distance metric itself does not need to encode directionality via negative numbers.

#### B. Explicit Absolute Value Wrapping (`std::abs`)
In `cc/input/scroll_snap_data.cc`, all 1D distance metrics are explicitly wrapped in `std::abs()` (from `<cmath>`). 
```cpp
// Conceptual representation of Blink's internal logic:
float distance = std::abs(candidate_position - base_position);
```
In IEEE 754 floating-point arithmetic, `std::abs(x)` clears the sign bit, guaranteeing a return value in the range $[0.0, +\infty)$ (barring `NaN`).

#### C. Euclidean Norm Properties
For 2D snapping (`gfx::Vector2dF::Length()`), the distance is derived from the square root of the sum of squares (`std::hypot(dx, dy)` or $\sqrt{dx^2 + dy^2}$). Because the square of any real number is non-negative, and the principal square root function `std::sqrt` is strictly non-negative for real inputs, $D_{2D} \ge 0$ is mathematically guaranteed.

#### D. Overlapping Snap Areas (Covering)
If a `SnapArea` is larger than the `Snapport` (e.g., a tall image in a small viewport), and the user scrolls *within* the area, the area is considered "covering" the snapport. 
* In this scenario, the distance $D$ to the snap area is explicitly clamped to **$0.0f$**, preventing any "inside-out" negative boundary calculations.

#### E. Sentinel Values and `base::optional`
Historically, some engines use `-1.0f` as a sentinel value for "invalid distance." Blink avoids this anti-pattern. Instead, Blink uses:
1. `std::optional<SnapSearchResult>` to represent the absence of a valid snap target.
2. `std::numeric_limits<float>::max()` (or `INFINITY`) as the initial accumulator value in the minimization loop:
```cpp
float smallest_distance = std::numeric_limits<float>::max();
```
This ensures the comparison domain remains strictly within $[0.0, \text{FLT\_MAX}]$.

### 4. Audit Conclusion
Blink’s `cc::SnapContainerData` guarantees non-negativity in scroll snap distance evaluations. Directionality (sign) and magnitude (distance) are strictly decoupled: sign is consumed during the boolean visibility/directionality filter phase, while magnitude is enforced as non-negative via `std::abs`, Euclidean geometry, and zero-clamping during the minimization phase. 

**END AUDIT LOG — AGENT 329**