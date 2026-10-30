**AUDIT REPORT: Blink `Document::readyState` Monotonic Progression**
**Agent ID:** 458
**Target Component:** `third_party/blink/renderer/core/dom/document.cc` (`Document::SetReadyState`)
**Subject:** State Machine Monotonicity and Transition Lifecycle

---

### 1. Executive Summary
In the Chromium Blink rendering engine, `Document.readyState` represents the loading status of the document. Per the HTML Living Standard and Blink’s internal state machine assertions, the progression of `readyState` for any single `Document` instance is **strictly monotonic**. Once a state advances, it cannot regress.

### 2. State Enumeration & Order
Blink represents the states internally using the `DocumentReadyState` enum, which maps directly to the DOM strings exposed to JavaScript:

1. **`kLoading` (`"loading"`)**: The `Document` is undergoing parsing. Subresources may or may not be fetching.
2. **`kInteractive` (`"interactive"`)**: The HTML parser has finished constructing the DOM tree. Subresources (images, stylesheets, frames) are still being fetched/processed.
3. **`kComplete` (`"complete"`)**: The parser has finished, and all critical subresources have finished loading (or failed to load).

**Monotonicity Rule:** 
$$\text{kLoading} \longrightarrow \text{kInteractive} \longrightarrow \text{kComplete}$$

---

### 3. Detailed Transition Progression

#### Phase 0: Initialization (`kLoading`)
* **Trigger:** Instantiation of the `Document` object (via `DocumentInit`).
* **Blink Internals:** The `ready_state_` member variable is initialized to `kLoading`.
* **Events Fired:** None. The transition to the initial state is silent.
* **Exception (`about:blank`):** While synchronous initial `about:blank` documents technically transition to `complete` almost immediately during frame initialization, they still structurally pass through the state machine.

#### Phase 1: `kLoading` $\rightarrow$ `kInteractive`
* **Trigger:** The HTML parser processes the end of the input stream (`HTMLDocumentParser::PrepareToStopParsing()` $\rightarrow$ `Document::FinishedParsing()`).
* **Blink Internals:** 
  1. `Document::SetReadyState(kInteractive)` is invoked.
  2. Internal state `ready_state_` updates.
  3. **Event Dispatch:** Blink synchronously fires the `readystatechange` event on the `Document`.
* **Subsequent Actions:** Immediately following this state change, Blink executes `deferred` scripts and subsequently fires the `DOMContentLoaded` event.

#### Phase 2: `kInteractive` $\rightarrow$ `kComplete`
* **Trigger:** The `FrameLoader` determines all blocking resources (images, subframes, stylesheets, pending scripts) have completed fetching. (`Document::CheckCompleted()` $\rightarrow$ `Document::ImplicitClose()`).
* **Blink Internals:**
  1. `Document::SetReadyState(kComplete)` is invoked.
  2. Internal state `ready_state_` updates.
  3. **Event Dispatch:** Blink synchronously fires the `readystatechange` event on the `Document`.
* **Subsequent Actions:** Immediately following the `readystatechange` event, `DOMWindow::DispatchLoadEvent()` is triggered, firing the `load` event on the `window` object.

---

### 4. Edge Cases & Audit Verification

#### A. Aborted Loads (`window.stop()`)
If a user or script aborts the document load while in the `kLoading` state:
* Blink does **not** leave the document in `kLoading`, nor does it skip states without updating.
* The parser is forcibly stopped, driving the state to `kInteractive`, and because no pending resources remain, it immediately cascades to `kComplete`. Monotonicity is preserved, though the transition from `kLoading` $\rightarrow$ `kInteractive` $\rightarrow$ `kComplete` happens within the same call stack.

#### B. Navigations
A navigation does **not** reset `readyState` to `kLoading`. Instead, the browser creates a *new* `Document` instance for the new navigation, which starts at `kLoading`. The old `Document` remains at `kComplete` (or whatever state it achieved before destruction/BFCache storage).

#### C. `document.open()` (The Perceived Violation)
**Audit Note:** `document.open()` is the *only* web-platform mechanism where a developer observes the same `Document` object reference reverting its `readyState` from `"complete"` back to `"loading"`.
* **Blink Implementation:** When `Document::open()` is called on a `kComplete` document, Blink performs an internal teardown (`CancelParsing()`, clearing the DOM tree, resetting the parser). 
* **State Reset:** It explicitly overrides the state machine to reset `ready_state_` back to `kLoading` to accommodate the incoming `document.write()` stream, which will conclude with `document.close()` and repeat the monotonic progression to `kInteractive` and `kComplete`.
* **Verdict:** While the JS wrapper object identity remains the same, logically, `document.open()` initializes a new document lifecycle, preserving monotonicity *per document load lifecycle*.

### 5. Blink Enforcement (`DCHECK`)
Within `Document::SetReadyState(DocumentReadyState ready_state)`, Blink enforces this progression. If an internal bug attempts to transition from `kComplete` to `kInteractive`, or `kInteractive` to `kLoading` (outside of the explicit `document.open()` teardown path), debug builds of Chromium will crash via `DCHECK` assertions, preventing state regression.

**Audit Status:** Verified. Blink adheres strictly to monotonic progression per document lifecycle. 
*Agent 458 signing off.*