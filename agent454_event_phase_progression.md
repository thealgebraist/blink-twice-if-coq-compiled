**AUDIT REPORT: BLINK EVENT DISPATCH PHASES**
**Auditor:** Agent 454  
**Subject:** DOM Event Dispatch Architecture (`third_party/blink/renderer/core/events/event_dispatcher.cc`)  
**Status:** Verified Strict Ordering

Per standard W3C DOM Event specifications and internal Chromium/Blink implementation (`EventDispatcher::Dispatch`), event propagation through the `EventPath` adheres to a strict, sequential 3-phase ordering. Prior to Phase 1, the `EventPath` is calculated statically based on the DOM/Shadow DOM tree structure at the moment dispatch begins.

Here is the strict ordering of the 3 phases audited within the Blink engine:

---

### **Phase 1: CAPTURING_PHASE (Value: `1`)**
* **Blink Method:** `EventDispatcher::DispatchEventAtCapturing()`
* **Direction:** Root (`Window`) $\rightarrow$ Parent of Target.
* **Execution Order:** The dispatcher iterates **top-down** through the pre-calculated `EventPath` (from the highest ancestor down to the immediate parent of the target node).
* **Listener Filtering:** Only event listeners registered with the `capture` flag set to `true` (`useCapture = true`) are invoked.
* **Shadow DOM Handling:** If the event crosses a Shadow Root boundary, `EventPath` adjusts the ` target` and `relatedTarget` properties (retargeting) as it descends, unless the event is restricted by `composed: false`.

### **Phase 2: AT_TARGET (Value: `2`)**
* **Blink Method:** `EventDispatcher::DispatchEventAtTarget()`
* **Direction:** Stationary (Target Node only).
* **Execution Order:** The event reaches the actual `event.target` (or the retargeted host if firing at a Shadow Host). 
* **Listener Filtering:** **Both** capturing (`capture: true`) and bubbling (`capture: false`) listeners registered on the target node are invoked. 
* **Strict Sub-Ordering:** Within Blink’s `EventTarget::FireEventListeners`, listeners at the target phase are executed strictly in the **order of their registration**, regardless of whether they were registered as capture or bubble listeners (per the updated DOM Living Standard).

### **Phase 3: BUBBLING_PHASE (Value: `3`)**
* **Blink Method:** `EventDispatcher::DispatchEventAtBubbling()`
* **Direction:** Parent of Target $\rightarrow$ Root (`Window`).
* **Execution Pre-condition:** This phase executes **if and only if** `event.bubbles` is `true`. If `false`, the dispatcher skips directly to post-dispatch finalization.
* **Execution Order:** The dispatcher iterates **bottom-up** (in reverse order of the `EventPath`), starting from the target's immediate parent back up to the `Document` and `Window`.
* **Listener Filtering:** Only event listeners registered with the `capture` flag set to `false` (the default) are invoked.

---

### **Audit Notes on Flow Control & Termination**
At any point during these 3 phases, strict ordering can be deliberately halted by the following flags checked by `EventDispatcher`:

1. **`stopPropagation()`:** Sets the `propagation_stopped_` flag in Blink. The current node finishes executing all of its remaining eligible listeners for the current phase, after which the dispatcher immediately aborts subsequent phases.
2. **`stopImmediatePropagation()`:** Sets the `immediate_propagation_stopped_` flag. Execution halts immediately; no further listeners on the *current* node or *any subsequent* nodes/phases are invoked.
3. **Default Action (Post-Phase 3):** Only after all 3 phases have concluded (even if propagation was stopped), Blink checks `!event.defaultPrevented()`. If allowed, `Node::DefaultEventHandler` is invoked to execute native browser behaviors (e.g., following a link, submitting a form). 

**End of Report.**