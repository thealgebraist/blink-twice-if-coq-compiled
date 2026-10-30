**AUDIT REPORT: BLINK SCROLL SNAP SYSTEM**
**Auditor:** Agent 330
**Target:** `cc::SnapContainerData` / `blink::ScrollSnapType`
**Subject:** `scroll-snap-stop: always` Clamping Mechanics

---

### 1. Executive Summary
In the Blink rendering engine (working in tandem with the Chromium Compositor `cc`), `scroll-snap-stop: always` prevents a fling, programmatic scroll, or momentum scroll from bypassing intermediate snap points. **"Clamping"** is the mathematical constraint mechanism used by Blink to intercept a projected scroll trajectory and force it to terminate at the * very next* snap area in the direction of movement, rather than the snap area closest to the natural end of the momentum curve.

### 2. The Clamping Pipeline

When a user initiates a scroll gesture (e.g., touchpad fling, touch swipe, or mouse wheel), the input is routed to the compositor thread (or main thread in slow-scroll scenarios). The clamping mechanism operates in three distinct phases:

#### Phase 1: Physics Projection (Unclamped Target)
Before snap logic is applied, the input system calculates the **intended end position** based on the current scroll velocity and friction curves. 
*   `start_position`: Where the scroll began (or current offset).
*   `intended_end_position`: Where the scroll would naturally come to rest without snapping.
*   `displacement`: `intended_end_position - start_position`.

#### Phase 2: Candidate Collection (`cc/input/scroll_snap_data.cc`)
The compositor queries `SnapContainerData::FindSnapPosition()`. The engine iterates through all registered `SnapAreaData` objects within the container to find valid snap targets along the scroll axis.

Usually, for `scroll-snap-stop: normal`, the engine simply looks for the snap offset closest to the `intended_end_position`. However, if *any* `SnapAreaData` has the flag `must_snap` (the internal representation of `scroll-snap-stop: always`), the clamping algorithm is triggered.

#### Phase 3: Trajectory Interception (The Clamp)
The engine establishes a directional search bound between `start_position` and `intended_end_position`.

1.  **Directional Filtering:** 
    *   If scrolling forward (`displacement > 0`), the engine looks for `must_snap` areas where `snap_offset > start_position` and `snap_offset < intended_end_position`.
    *   If scrolling backward (`displacement < 0`), it looks for `must_snap` areas where `snap_offset < start_position` and `snap_offset > intended_end_position`.
2.  **Finding the Clamp Bound:** 
    The engine identifies the `must_snap` candidate that is **closest to the `start_position`** (not the end position).
3.  **Applying the Clamp:**
    The `intended_end_position` is hard-clamped to this first encountered `must_snap` offset. All subsequent `normal` or `always` snap points further along the original momentum vector are discarded for this gesture.

### 3. Edge Cases & Heuristics Audited

During the audit of the `always` clamping logic, several critical edge-case handlers in Blink's implementation must be noted:

*   **The Epsilon Escape ( escaping the current snap point):**
    If the scroll starts *already* resting on a `scroll-snap-stop: always` point, strict mathematical comparison (`>=`) would clamp the scroll to its own starting position, locking the user in place. Blink utilizes a floating-point epsilon heuristic to ignore the currently snapped element, allowing the scroll to escape and clamp to the *next* available target.
*   **Large Elements (Visibility Range):**
    If a `scroll-snap-stop: always` element is larger than the scrollport (the "covering" case), Blink does not clamp to the edges if the user is scrolling *within* the element. Clamping only engages when the scroll trajectory attempts to exit the element or bypass its initial snap alignment.
*   **2D Axis Alignment Interference:**
    In a 2D scroll container (`scroll-snap-type: both`), clamping is evaluated independently per axis (X and Y). However, if clamping on the X-axis forces the scroll to stop at an element that is *not* aligned on the Y-axis, Blink must reconcile visibility to ensure the clamped X position doesn't result in the target element being off-screen vertically.
*   **Input Type Exclusions:**
    Clamping is primarily applied to gestures with momentum (flings, wheel ticks, `scrollBy`). Direct manipulation (e.g., dragging the scrollbar thumb) generally bypasses intermediate `always` clamping until the thumb is released, at which point it acts as a `normal` snap to the nearest point, preventing a "stuttering" drag experience.

### 4. Relevant Source Files (Chromium Tree)
For further deep-dive verification, reference the following paths:
*   `third_party/blink/renderer/core/page/scrolling/snap_coordinator.cc` (DOM to CC translation)
*   `cc/input/scroll_snap_data.cc` (`SnapContainerData::FindSnapPosition` and `SnapSelectionStrategy`)
*   `cc/input/snap_selection_strategy.cc` (`EndAndDirectionStrategy::ShouldRespectSnapStop`)

**Audit Conclusion:** Blink's `scroll-snap-stop: always` clamping functions by shifting the evaluation priority from the *end* of the physics curve to the *start* of the physics curve, truncating the vector at the first valid `must_snap` intersection. **Status: Verified.**