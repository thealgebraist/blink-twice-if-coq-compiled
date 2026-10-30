**AUDIT LOG: AGENT 456**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/dom/events/`)
**SUBJECT:** EventListener Registration & Invocation FIFO Order

---

### 1. Executive Summary
Blink strictly adheres to the **WHATWG DOM Specification** regarding the registration and invocation of `EventListener` instances. Listeners registered on a single `EventTarget` for a specific event type are stored in a contiguous vector and invoked in a strict **First-In, First-Out (FIFO)** sequence, determined by the exact moment of their initial registration.

---

### 2. Data Structure Architecture
At the core of Blink's event system is the `EventTargetData` class, which holds an `EventListenerMap`.

*   **Mapping:** `EventListenerMap` maps an `AtomicString` (the event `type`, e.g., `"click"`) to an `EventListenerVector`.
*   **Storage (`EventListenerVector`):** Defined as `HeapVector<RegisteredEventListener, 1>`.
*   **FIFO Mechanism:** When `addEventListener` is called, Blink appends the new `RegisteredEventListener` to the end of this `HeapVector` using `push_back()`. Because new elements are appended to the tail and iteration occurs from index `0` to `size() - 1`, FIFO order is naturally enforced at the memory level.

---

### 3. Registration Rules & Edge Cases (Deduplication)
Before appending a listener to the `EventListenerVector`, Blink performs a deduplication check (`EventListenerMap::Add`). A listener is uniquely identified by a 3-tuple:
1.  `EventListener*` (The callback reference)
2.  `use_capture` (Boolean flag)
3.  `passive` / `once` / `signal` configurations (though only `capture` affects tuple uniqueness for deduplication).

#### Audit Findings on FIFO Integrity during Registration:
*   **Duplicate Registration:** If `addEventListener` is called with an identical `type`, `listener`, and `capture` flag as an already registered listener, **it is ignored**. The existing listener retains its original position in the FIFO queue; it is *not* moved to the back of the queue.
*   **Phase Separation (`capture` vs. `bubble`):** Blink stores both `capture: true` and `capture: false` listeners in the *same* `EventListenerVector` in the exact FIFO order they were added. Phase filtering occurs during the *invocation* loop, not through separate storage queues.
    *   *Exception:* If the exact same callback function is registered twice—once with `capture: true` and once with `capture: false`—Blink treats them as two distinct `RegisteredEventListener` entries, each maintaining its respective FIFO position.

---

### 4. Invocation Mechanics (`EventTarget::FireEventListeners`)
When an event is dispatched to an `EventTarget`, `FireEventListeners` retrieves the `EventListenerVector` for the event's type and iterates from index `0` upwards.

#### A. Phase-Based Filtering
As the loop iterates through the vector in FIFO order, it checks the current `eventPhase`:
1.  **CAPTURING_PHASE:** Listeners with `capture == false` are skipped.
2.  **BUBBLING_PHASE:** Listeners with `capture == true` are skipped.
3.  **AT_TARGET:** 
    *   In modern Blink (per updated DOM specs), listeners on the target itself are evaluated based on the phase currently being processed by the `EventDispatcher` (first the capturing loop runs, then the bubbling loop runs). Within each pass, FIFO order is strictly maintained.
    *   *(Legacy Note: For certain shadow DOM or non-bubbling edge cases, `AT_TARGET` evaluates in pure registration order regardless of the `capture` flag, though standard dispatch separates them into two FIFO passes).*

#### B. Mutation Resilience (Modifying the Queue Mid-Flight)
A critical aspect of the FIFO audit is how Blink handles mutations to the `EventListenerVector` *while* it is actively iterating through it (e.g., Listener A adds or removes Listener B during execution).

Instead of cloning the vector (which is memory-expensive), Blink uses index tracking (`size` and `i`):

1.  **Dynamic Addition (Snapshot Enforcement):**
    *   Before the invocation loop begins, Blink snapshots the current size of the vector: `wtf_size_t size = entry.size();`.
    *   The loop condition is `while (i < size)`.
    *   **Result:** If a listener adds a new listener to the same `EventTarget` for the same event type during execution, it is pushed to the back of the vector (index $\ge$ `size`). It **will not** be invoked during the current event dispatch cycle.

2.  **Dynamic Removal (Index Adjustment):**
    *   If a listener removes an upcoming listener (or itself, e.g., via `{ once: true }`), Blink does two things:
        *   It marks the `RegisteredEventListener` flag `removed_` as `true` (as a safeguard).
        *   It physically erases the element from the `HeapVector`, shifting subsequent elements left.
    *   To prevent skipping the next element in the FIFO queue due to the left-shift, Blink notifies an active iterator tracker (`EventTargetData::firing_event_iterators_`). If the removed index is $\le$ the current loop index `i`, both `i` and `size` are decremented by 1.
    *   **Result:** Remaining listeners still execute in their exact relative FIFO order without skipping.

3.  **Halt Directives (`stopImmediatePropagation`):**
    *   Inside the FIFO loop, after each listener is invoked, Blink checks `event.ImmediatePropagationStopped()`.
    *   If `true`, the `while` loop breaks immediately, preventing any subsequent listeners in the FIFO queue from executing.

---

### 5. Execution Trace Example
**Setup on `element`:**
```javascript
element.addEventListener('click', ListenerA, false); // Index 0
element.addEventListener('click', ListenerB, true);  // Index 1
element.addEventListener('click', ListenerC, false); // Index 2
element.addEventListener('click', ListenerA, false); // Duplicate of Index 0 -> Ignored
element.addEventListener('click', ListenerD, true);  // Index 3
```

**Internal `EventListenerVector` State (FIFO):**
`[0: {A, bubble}, 1: {B, capture}, 2: {C, bubble}, 3: {D, capture}]`

**Invocation Order on `element.click()`:**
1.  **Capture Pass (`FireEventListeners` loop 1):**
    *   Index 0 (A): Skipped (is bubble)
    *   Index 1 (B): **INVOKED**
    *   Index 2 (C): Skipped (is bubble)
    *   Index 3 (D): **INVOKED**
2.  **Bubble Pass (`FireEventListeners` loop 2):**
    *   Index 0 (A): **INVOKED**
    *   Index 1 (B): Skipped (is capture)
    *   Index 2 (C): **INVOKED**
    *   Index 3 (D): Skipped (is capture)

**Final Execution Output:** `B -> D -> A -> C`

---
**AUDIT CONCLUSION:** Blink's `EventListener` implementation is **COMPLIANT**. FIFO order is guaranteed per event phase via contiguous vector allocation, duplicate suppression, and dynamic iterator adjustment during mid-dispatch mutations. 
**AGENT 456 SIGNING OFF.**