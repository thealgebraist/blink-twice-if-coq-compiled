**AUDIT LOG: AGENT 455**
**SUBJECT:** Blink Event Dispatch Loop Cessation via `stopPropagation()`
**TARGET SUBSYSTEM:** `third_party/blink/renderer/core/dom/events/`
**STATUS:** ACTIVE AUDIT

---

### 1. Executive Summary
This audit details the exact mechanical cessation of the DOM event dispatch loop within the Chromium Blink rendering engine when `Event.prototype.stopPropagation()` or `Event.prototype.stopImmediatePropagation()` is invoked. 

Loop cessation is not achieved via an immediate stack unwind or exception throw; rather, it relies on state-flag mutation on the `blink::Event` instance, which is polled at strict boundaries within the `EventDispatcher` loop architecture.

---

### 2. Flag Mutation Phase (`blink::Event`)
When JavaScript invokes a propagation termination method, V8 bindings route the call directly to the C++ `blink::Event` implementation (`event.h` / `event.cc`).

*   **`stopPropagation()`**: Sets the internal bitflag `propagation_stopped_ = true`.
*   **`stopImmediatePropagation()`**: Sets both `propagation_stopped_ = true` and `immediate_propagation_stopped_ = true`.

At the moment of invocation, the currently executing `EventListener` continues to run to completion. No interruption occurs within the active V8 execution frame.

---

### 3. Inner Loop Cessation (`EventTarget::FireEventListeners`)
Before returning control to the macro-level DOM tree traversal (`EventDispatcher`), the engine must resolve the micro-level listener loop on the *current* `Node` (`EventTarget`).

**Location:** `third_party/blink/renderer/core/dom/events/event_target.cc`

1.  `EventTarget::FireEventListeners` iterates over the ` EventListenerVector` registered for the specific event type on the current target.
2.  **Boundary Check (Immediate):** Inside the `while` loop iterating over listeners, immediately following the execution of `registered_listener.Callback()->InvokeAndReportException(...)`, the engine polls:
    ```cpp
    if (event.ImmediatePropagationStopped())
      break;
    ```
3.  **Result:** 
    *   If only `stopPropagation()` was called, `ImmediatePropagationStopped()` evaluates to `false`. The inner loop **continues**, firing all remaining listeners registered on the *same* `EventTarget` for the current phase.
    *   If `stopImmediatePropagation()` was called, the `break` statement executes, terminating the inner loop immediately. Subsequent listeners on the current node are bypassed.

---

### 4. Outer Loop Cessation (`EventDispatcher`)
Once `EventTarget::FireEventListeners` returns, control reverts to the primary orchestration class: `EventDispatcher`. The pre-calculated propagation path is stored in an `EventPath` object (an array of `NodeEventContext` instances representing the Shadow DOM and flat tree ancestors).

**Location:** `third_party/blink/renderer/core/dom/events/event_dispatcher.cc`

#### A. Capturing Phase (`DispatchEventPreProcess` / `DispatchEventAtCapturing`)
The dispatcher iterates *backwards* through the `EventPath` (from the Root/Window down to the target's parent).
```cpp
for (wtf_size_t i = event_->GetEventPath().size() - 1; i > 0; --i) {
  const NodeEventContext& event_context = event_->GetEventPath()[i];
  if (event_context.CurrentTargetSameAsTarget())
    continue;
  event_context.HandleLocalEvents(*event_);
  if (event_->PropagationStopped())
    return kDoneDispatching; // <-- CESSATION POINT 1
}
```
*   **Audit Note:** If `propagation_stopped_` is detected after `HandleLocalEvents` returns, the `for` loop is aborted via an early `return`. The event never reaches the `AT_TARGET` or `BUBBLING_PHASE`.

#### B. At-Target Phase (`DispatchEventAtTarget`)
If the Capturing phase completes without cessation, `DispatchEventAtTarget` is invoked on index `0` of the `EventPath`.
```cpp
event_->GetEventPath()[0].HandleLocalEvents(*event_);
if (event_->PropagationStopped())
  return kDoneDispatching; // <-- CESSATION POINT 2
```
*   **Audit Note:** In modern Blink, `AT_TARGET` listeners are often handled inline within the unified loop logic depending on the event's `bubbles()` attribute, but logically, if `PropagationStopped()` is true upon exiting index `0`, the method returns `kDoneDispatching`, bypassing the Bubbling phase.

#### C. Bubbling Phase (`DispatchEventAtBubbling`)
If the event is configured to bubble (`event_->bubbles() == true`) and survived the target phase, the dispatcher iterates *forwards* through the `EventPath` (from index `1` up to `size() - 1`).
```cpp
for (wtf_size_t i = 1; i < event_->GetEventPath().size(); ++i) {
  const NodeEventContext& event_context = event_->GetEventPath()[i];
  if (event_context.CurrentTargetSameAsTarget()) {
    // Handled in target phase, unless across Shadow DOM boundaries
    ...
  }
  event_context.HandleLocalEvents(*event_);
  if (event_->PropagationStopped())
    return kDoneDispatching; // <-- CESSATION POINT 3
}
```
*   **Audit Note:** Following each ancestor node's execution of `HandleLocalEvents`, `event_->PropagationStopped()` is polled. If `true`, the loop terminates immediately via `return kDoneDispatching`.

---

### 5. Post-Dispatch & Default Action Implications
When `kDoneDispatching` is returned from the phase methods to the master `EventDispatcher::Dispatch()` method:

1.  **State Reset:** `event_->SetCurrentTarget(nullptr)` and `event_->SetEventPhase(Event::PhaseType::kNone)` are executed to clean up the event wrapper.
2.  **Default Handler Execution (CRITICAL):** Termination of the dispatch loop via `stopPropagation()` **does not** prevent the execution of `DispatchEventPostProcess()`. 
    *   Unless `event_->defaultPrevented()` is *also* true, Blink will still iterate through the `EventPath` to invoke internal C++ `DefaultEventHandler` methods (e.g., following an `<a>` tag link, checking a checkbox). 
    *   `stopPropagation()` strictly ceases JS-observable DOM tree traversal; it does not halt native browser default actions.

**END OF AUDIT - AGENT 455**