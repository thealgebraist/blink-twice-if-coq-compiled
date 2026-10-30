**AUDIT LOG: AGENT 318**
**SUBJECT:** Chromium Blink Rendering Engine — `DocumentTimeline` Monotonic Clock Advancement
**STATUS:** IN PROGRESS
**CLASSIFICATION:** TECHNICAL AUDIT

---

### 1. EXECUTIVE SUMMARY
The `blink::DocumentTimeline` (implementing the Web Animations API `DocumentTimeline`) relies on a monotonically increasing clock to drive animations deterministically. It does **not** use wall-clock time (`base::Time`) to prevent erratic animation behavior during system clock adjustments (e.g., NTP syncs, daylight saving). Instead, it relies on `base::TimeTicks`, snapped to the compositor's vertical synchronization (VSync) intervals.

---

### 2. TIME SOURCE ORIGIN (`base::TimeTicks`)
*   **Underlying Mechanism:** The foundational clock is `base::TimeTicks::Now()`.
*   **OS-Level Mapping:** 
    *   **Linux/Android:** `clock_gettime(CLOCK_MONOTONIC)`
    *   **macOS/iOS:** `mach_absolute_time()`
    *   **Windows:** `QueryPerformanceCounter()` (QPC)
*   **Guarantee:** Strictly non-decreasing. It pauses when the system is suspended (asleep) and resumes upon wake, ensuring animations do not instantly jump to completion after a system sleep event.

---

### 3. CLOCK ADVANCEMENT PIPELINE (FRAME-BY-FRAME)
The `DocumentTimeline` clock does not advance continuously; it advances in discrete steps tied to the rendering pipeline’s `BeginMainFrame` stage.

#### Phase A: VSync Generation (Viz / Compositor)
1.  The GPU/Display Compositor generates a VSync signal.
2.  A `viz::BeginFrameArgs` struct is created, capturing the monotonic `frame_time` (the exact `base::TimeTicks` the VSync was triggered).
3.  This struct is dispatched to the Renderer process via Mojo IPC (`cc::Scheduler`).

#### Phase B: Page Animator Ingestion (Blink)
1.  The Renderer's compositor thread triggers `ProxyMain::BeginMainFrame`.
2.  Control passes to Blink via `WebFrameWidgetImpl::BeginMainFrame(base::TimeTicks frame_time)`.
3.  `PageAnimator::ServiceScriptedAnimations(frame_time)` is invoked. This is the master synchronisation point for both `requestAnimationFrame` (rAF) and `DocumentTimeline`.

#### Phase C: DocumentTimeline Tick
1.  `DocumentAnimator::ServiceScriptedAnimations` iterates through active documents and updates their respective `DocumentTimeline` instances.
2.  **The Latch:** `DocumentTimeline` does not query the OS clock directly during animation ticks. It latches onto the `frame_time` passed down from `BeginFrameArgs`. 
3.  This ensures that **all** animations and `rAF` callbacks executing within the same render frame observe the exact same timestamp, preventing visual tearing or out-of-sync spatial calculations.

---

### 4. TIME CALCULATION & ZERO-TIME OFFSET
The value exposed to JavaScript via `document.timeline.currentTime` is calculated relative to the document's navigation lifecycle, not system boot time.

$$\text{CurrentTime} = (\text{LastFrameTime} - \text{ZeroTime}) \times \text{PlaybackRate}$$

*   **`LastFrameTime`:** The `base::TimeTicks` provided by the latest `BeginMainFrame`.
*   **`ZeroTime`:** Established by `DocumentLoader` as the `reference_monotonic_time` (the exact `base::TimeTicks` corresponding to `performance.timeOrigin`, i.e., when navigation started).
*   **`PlaybackRate`:** Default is `1.0`. (Modifiable via DevTools/Inspector for slow-motion debugging).

---

### 5. SECURITY & EDGE-CASE MITIGATIONS

*   **Spectre/Meltdown Coarsening:** While `base::TimeTicks` has microsecond resolution internally, when `DocumentTimeline::currentTime` is exposed to the V8 JavaScript execution environment, it passes through `Performance::ClampTimeResolution()`. Unless the document is cross-origin isolated (`COOP`/`COEP` headers present), the monotonic timestamp is coarsened (typically to 100 microseconds) and jittered to prevent side-channel timing attacks.
*   **Background Tab Throttling:** When a tab is backgrounded (`PageVisibilityState::kHidden`), the `cc::Scheduler` stops sending `BeginMainFrame` signals (or throttles them to 1Hz). Consequently, the `DocumentTimeline` clock ceases to advance, effectively freezing main-thread animations until visibility is restored, at which point it leaps forward to the new `frame_time`.
*   **Compositor-Thread Animations:** Animations running on the compositor thread (`cc::AnimationHost`) run on a duplicate timeline synchronized with the same `ZeroTime`, advancing via `BeginImplFrame` ticks even if the main thread is blocked (jank).

---

### 6. AUDIT CONCLUSION
The Blink `DocumentTimeline` monotonic clock advancement is **compliant** with W3C Web Animations specifications. Time advancement is strictly deterministic, immune to system-clock tampering, synchronized across the rendering pipeline, and appropriately clamped at the JS boundary. 

**END OF REPORT — AGENT 318**