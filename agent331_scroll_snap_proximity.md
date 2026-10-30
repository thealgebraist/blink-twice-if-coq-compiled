**AUDIT LOG: BLINK RENDERING ENGINE**
**Auditor:** Agent 331
**Component:** `cc/input/scroll_snap_data.h` & `cc/input/snap_selection_strategy.cc`
**Subject:** CSS Scroll Snap `proximity` Threshold Evaluation Mechanics

---

### 1. Executive Summary
In the Chromium (Blink/CC) compositor architecture, `scroll-snap-type: [axis] proximity` differs from `mandatory` by introducing an escape hatch: the user may rest at a non-snapped scroll offset *unless* the intended scroll offset falls within a calculated distance (the **Proximity Threshold**) of a valid snap target. 

Below is the technical breakdown of how the Compositor Thread (`cc`) defines, calculates, and checks this threshold.

---

### 2. Source of Truth
While Blink (`third_party/blink/renderer/core/page/scrolling/snap_coordinator.cc`) parses the CSS and extracts layout geometry, the actual proximity threshold evaluation occurs on the compositor thread during scroll gesture resolution to ensure 60/120fps responsiveness.

*   **Data Structure:** `cc::SnapContainerData`
*   **Constant Definition:** `kProximityRatio` (historically `1.0 / 3.0`)
*   **Evaluation Logic:** `cc::SnapContainerData::FindSnapPosition()`

---

### 3. The Proximity Threshold Calculation

The CSS Scroll Snap Module Level 1 specification intentionally leaves the exact proximity threshold UA-defined. Chromium defines this threshold as a fixed ratio of the **scrollport’s** (viewport's) size along the relevant axis.

#### 3.1. The Constant
```cpp
// Defined in cc/input/scroll_snap_data.cc (or associated header)
constexpr float kProximityRatio = 1.0f / 3.0f;
```

#### 3.2. Initialization (`SnapContainerData`)
When a `SnapContainerData` object is constructed or updated with a new `rect` ( representing the scrollport bounds), the `proximity_range_` vector (`gfx::PointF`) is dynamically calculated:

$$\text{Proximity Range}_x = \text{Scrollport Width} \times \frac{1}{3}$$

$$\text{Proximity Range}_y = \text{Scrollport Height} \times \frac{1}{3}$$

```cpp
// Conceptual representation in Blink/CC bridge
gfx::PointF proximity_range(
    scrollport_rect.width() * kProximityRatio,
    scrollport_rect.height() * kProximityRatio
);
container_data.set_proximity_range(proximity_range);
```

---

### 4. The Threshold Check Execution

When a scroll gesture concludes (or updates), `SnapSelectionStrategy` provides the **intended position** (incorporating inertial fling physics if applicable) and the **base position**. `SnapContainerData` then searches for candidate snap targets.

#### Step 1: Candidate Gathering
The engine iterates through all `SnapAreaData` objects registered to the container and calculates the distance ($\Delta$) between the `intended_position` and the snap area's target snap offset:

$$\Delta_{\text{axis}} = | \text{Target Snap Offset}_{\text{axis}} - \text{Intended Scroll Offset}_{\text{axis}} |$$

#### Step 2: The Gatekeeper Check
Before a candidate is accepted as the winning snap position for a given axis, it must pass the strictness evaluation. 

If `scroll_snap_type.strictness == SnapStrictness::kMandatory`, the distance check is bypassed (all valid visible candidates are considered, and the closest wins).

If `scroll_snap_type.strictness == SnapStrictness::kProximity`, the engine executes the threshold check:

```cpp
// Inside cc::SnapContainerData::FindSnapPositionForAxis (Simplified for audit)
float smallest_distance = std::numeric_limits<float>::max();
std::optional<SnapSearchResult> closest_candidate;

for (const SnapSearchResult& candidate : candidates) {
  if (!strategy.IsValidSnapPosition(axis, candidate.snap_offset()))
    continue;

  float distance = std::abs(candidate.snap_offset() - intended_position);
  if (distance < smallest_distance) {
    smallest_distance = distance;
    closest_candidate = candidate;
  }
}

// THE PROXIMITY THRESHOLD CHECK
if (scroll_snap_type_.strictness == SnapStrictness::kProximity) {
  float threshold = (axis == SearchAxis::kX) ? proximity_range_.x() 
                                             : proximity_range_.y();
  if (smallest_distance > threshold) {
    return std::nullopt; // Abort snap; allow free-scroll rest at intended_position
  }
}

return closest_candidate;
```

---

### 5. Edge Cases & Audit Nuances

As Agent 331, I must highlight three critical behavioral nuances during this check:

1.  **Fling / Momentum Scrolling (`EndAndDirectionStrategy`):**
    The proximity check is evaluated against the **predicted end position** of the fling, *not* the scroll offset where the user lifted their finger. If a user flings hard and the physics engine predicts the scroll will naturally coast to a stop within `0.33 * viewport_size` of a snap point, the threshold check passes, and the physics curve is adjusted to land precisely on the snap point.
2.  **2D Axis Independence (and Mutual Visibility):**
    In a `both proximity` configuration, X and Y thresholds are checked independently using their respective viewport dimensions. However, Chromium enforces **mutual visibility**: if snapping on the X-axis (passing the X proximity check) would cause the chosen Y-axis element to move out of the viewport, the reconciliation algorithm in `FindSnapPosition()` may invalidate the snap or fall back to an alternative candidate.
3.  **Large Elements (Covering the Scrollport):**
    If a `SnapArea` is larger than the scrollport itself, and the user's intended scroll position is *completely inside* that element's bounds (spanning the entire viewport), Chromium will generally **not** force a snap to the edges unless the intended position is within the `1/3` proximity range of the element's snap-aligned start/end edge. This prevents trapping the user from reading the middle of a tall element—a behavior shared with `mandatory`, though `proximity` relies heavily on the threshold check to exit the edges gracefully.

---
**Audit Status:** COMPLETE. 
**Conclusion:** Blink/CC's proximity check is deterministic, executing on the compositor thread using a hardcoded `33.33%` scrollport dimension scalar against the `SnapSelectionStrategy`'s intended terminal offset.