**AUDIT LOG: AGENT 319**  
**TARGET SYSTEM:** Chromium / Blink Rendering Engine (`cc/animation`, `third_party/blink/renderer/core/animation`)  
**SUBJECT:** Animation Play State Machine Transition Invariants  

---

### 1. System Overview & State Definitions
In the Blink Web Animations API implementation (`blink::Animation`), the `AnimationPlayState` is not stored as an explicit, mutable state variable. Instead, it is a **derived state** calculated deterministically from the animation's internal timing parameters, synchronization tokens, and timeline attachment.

The canonical states defined by the W3C specification and implemented in `Animation::CalculateAnimationPlayState()` are:
*   **`kIdle`**: Unresolved `current_time` AND no pending tasks.
*   **`kPending`**: There is a pending play or pause task awaiting synchronization with the compositor (`cc`) or the next frame tick.
*   **`kRunning`**: Resolved `current_time`, not paused, playback rate $\neq 0$, and outside the finished boundary.
*   **`kPaused`**: `paused_` flag is true (or `hold_time_` is locked without an active progression).
*   **`kFinished`**: Playback rate $> 0$ and `current_time` $\ge$ `EffectEnd()`, OR playback rate $< 0$ and `current_time` $\le 0$.

---

### 2. Core State Machine Invariants
For a state transition $S_i \rightarrow S_j$ to be valid within Blink, the following global invariants must hold across the Main-Compositor thread boundary:

#### Invariant I: The Time-Anchor Mutual Exclusivity
At the conclusion of any state transition, an animation cannot simultaneously rely on both `start_time_` and `hold_time_` to calculate its `current_time`, except during a `kPending` resolution phase.
$$\neg (\text{start\_time\_}.has\_value() \land \text{hold\_time\_}.has\_value()) \lor (\text{State} == \text{kPending})$$
*   **Audit Note:** Violation of this invariant causes time-drift between the Blink main thread and the `cc::AnimationHost` on the compositor thread.

#### Invariant II: The Compositor Synchronization Gate (`kPending` Mediation)
Transitions from non-active states (`kIdle`, `kPaused`) to `kRunning` **must** pass through `kPending` if the timeline is active.
$$S \in \{\text{kIdle}, \text{kPaused}\} \xrightarrow{\text{play()}} \text{kPending} \xrightarrow{\text{ OnNextFrame() }} \text{kRunning}$$
*   **Condition:** `pending_play_` is set to `true`. The transition to `kRunning` is blocked until the compositor provides a monotonic frame timestamp (`base::TimeTicks`), binding `start_time_`.

#### Invariant III: The Boundary Clamping Invariant (`kFinished`)
An animation may only enter or remain in the `kFinished` state if its `hold_time_` is clamped to the effect boundary and `start_time_` is cleared (or synchronized to the exact boundary limit).
*   If `EffectivePlaybackRate() > 0`: `current_time` $\ge$ ` TargetEffect()->SpecifiedTiming().IterationDuration()`
*   If `EffectivePlaybackRate() < 0`: `current_time` $\le 0$
*   **Zero-Rate Exception:** If `EffectivePlaybackRate() == 0`, the animation can **never** transition from `kRunning` to `kFinished` via natural time progression.

---

### 3. Transition Matrix & Specific Invariants

#### A. Transitions to `kIdle` (The Reset Vector)
*Trigger:* `cancel()`
*   **Pre-state:** Any ($S \in \text{All}$)
*   **Post-state:** `kIdle`
*   **Transition Invariants:**
    1. `hold_time_` = `std::nullopt`
    2. `start_time_` = `std::nullopt`
    3. `pending_pause_` = `false`, `pending_play_` = `false`
    4. If `ready_promise_` is unresolved, it must be **rejected** with `AbortError` (unless detached).
    5. Compositor element ID mapping must be invalidated via `DestroyCompositorAnimation()`.

#### B. Transitions to `kPending` (The Async Staging Vector)
*Triggers:* `play()`, `pause()`, `reverse()`, or `updatePlaybackRate()` while running.
*   **Pre-state:** `kIdle`, `kPaused`, `kRunning`, `kFinished`
*   **Post-state:** `kPending`
*   **Transition Invariants:**
    1. `pending_play_ == true` $\lor$ `pending_pause_ == true`.
    2. A microtask or compositor commit callback (`NotifyReady()`) must be scheduled in the `DocumentTimeline`.
    3. If transitioning from `kFinished` via `play()`, `hold_time_` must be reset to `0` (if rate $> 0$) or `EffectEnd()` (if rate $< 0$) *before* entering `kPending`.

#### C. Transitions from `kPending` (The Resolution Vector)
*Trigger:* `CommitPendingPlay()` or `CommitPendingPause()` (invoked via `Animation::NotifyReady(base::TimeTicks ready_time)`).
*   **Pre-state:** `kPending`
*   **Post-state:** `kRunning`, `kPaused`, or `kFinished`
*   **Transition Invariants:**
    1. `ready_time` must be a valid, monotonic timestamp ($\ge$ timeline zero time).
    2. **If `pending_pause_`:** `hold_time_` is locked using `ready_time`; `start_time_` is nulled. State becomes `kPaused`.
    3. **If `pending_play_`:** `start_time_` is calculated as:
       $$\text{start\_time\_} = \text{ready\_time} - \frac{\text{hold\_time\_}}{\text{playback\_rate\_}}$$
       `hold_time_` is nulled. State becomes `kRunning` (or immediately `kFinished` if out-of-bounds).
    4. `ready_promise_` is **resolved**.

#### D. Transitions to `kFinished` (The Completion Vector)
*Triggers:* Timeline tick (`Update()`), `finish()`, or `setCurrentTime()` to boundary.
*   **Pre-state:** `kRunning`, `kPending`, `kPaused` (only via `finish()`)
*   **Post-state:** `kFinished`
*   **Transition Invariants:**
    1. **Via `finish()` (Synchronous):** Bypasses `kPending`. `pending_play_` and `pending_pause_` are forcibly cleared. `start_time_` is retroactively computed based on current timeline time.
    2. **Via Timeline Tick (Asynchronous):** `UpdateFinishedState()` detects boundary crossing. `hold_time_` is locked to the boundary limit.
    3. `finished_promise_` is resolved, and the `finish` DOM event is queued.
    4. Compositor animation is marked as finished and removed from the active ticking list on the `cc` thread to prevent unnecessary impl-thread wakeups.

---

### 4. Edge-Case Audit Vulnerabilities (Agent 319 Notes)

1.  **Detached Timeline Starvation:**
    *   *Condition:* `Animation` is associated with a `DocumentTimeline` whose `Document` is inactive/detached, or a `ScrollTimeline` with no active scroller.
    *   *Invariant:* An animation with an inactive timeline cannot resolve a `kPending` state because `ready_time` is unobtainable. The state machine must remain locked in `kPending` (or `kIdle` if no `hold_time_` was computable) without leaking memory via unresolved `ScriptPromiseProperty` objects.
2.  **Mutating `playbackRate` Mid-Flight:**
    *   *Condition:* Direct assignment to `animation.playbackRate` (deprecated synchronous method) vs `animation.updatePlaybackRate()` (asynchronous).
    *   *Invariant:* `updatePlaybackRate()` *must* force a transition to `kPending` (`pending_play_ = true`) to seamlessly recalculate `start_time_` on the next frame without causing a visual jump on the compositor thread.
3.  **The "Paused-at-Boundary" Ambiguity:**
    *   *Condition:* Animation is paused at `current_time == EffectEnd()`.
    *   *Invariant:* `kPaused` strictly supersedes `kFinished`. Even if `current_time` satisfies the completion boundary, if `paused_ == true`, the state machine **must** report `kPaused` (or `kPending` if a pause is uncommitted).

**STATUS:** Audit parameters logged. State machine invariants verified against Blink revision specifications. **END LOG.**