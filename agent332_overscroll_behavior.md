**AUDIT LOG: BLINK RENDERING ENGINE (CHROMIUM)**
**AUDITOR:** Agent 332
**SUBJECT:** Scroll Propagation Isolation & Overscroll Chaining Mechanics
**STATUS:** ACTIVE AUDIT

---

### 1. ARCHITECTURAL OVERVIEW
In the Blink rendering engine, scroll propagation (also known as "scroll chaining") is the mechanism by which unconsumed scroll deltas are passed up the DOM/Layer tree from a target scrollable area to its ancestor scrollable areas, eventually reaching the `RootScroller` (viewport) and triggering browser-level overscroll affordances (e.g., glow effects, rubber-banding, pull-to-refresh, or swipe-to-navigate).

**Scroll Propagation Isolation** is primarily controlled via the CSS property `overscroll-behavior` (`x`, `y`) and enforced across two distinct execution environments: the **Compositor Thread (CC)** for fast-path scrolling, and the **Main Thread (Blink)** for slow-path scrolling and DOM event dispatch.

---

### 2. THE SCROLL LATCHING & CHAINING PIPELINE

Before evaluating isolation, Blink establishes a **Scroll Chain**:
1. **Hit Testing (`GestureScrollBegin`):** When an input gesture begins, the browser process routes the event to the renderer's Compositor Thread. CC performs a hit test against the `ScrollTree` to find the innermost `ScrollNode` capable of scrolling along the input axis.
2. **Scroll Latching:** Blink latches onto the first valid `ScrollNode`. For the duration of the gesture (`GestureScrollUpdate` stream), scroll deltas are applied primarily to this latched node.
3. **Boundary Exhaustion:** If the latched `ScrollNode` reaches its scroll extent (scroll offset == 0 or `max_scroll_offset`), any remaining delta in the frame is classified as **Unused Scroll Delta** (Overscroll).
4. **Ancestor Resolution:** By default (`overscroll-behavior: auto`), during the initial `GestureScrollBegin` or dynamically via scroll chaining, if a node cannot consume the delta, the engine traverses up the `ScrollTree` parent pointers to build a chain of eligible scroll ancestors.

---

### 3. ISOLATION MECHANICS (`overscroll-behavior`)

Blink translates the CSS `overscroll-behavior` property into bitmasks on the `ComputedStyle` object on the Main Thread, which are then pushed to the Compositor Thread via `cc::OverscrollBehavior` attached to the `cc::ScrollNode`.

#### A. `overscroll-behavior: auto` (Default)
* **Local Overscroll:** Allowed.
* **Scroll Chaining:** Enabled. Unused deltas bubble up the `ScrollTree`.
* **Browser Affordances:** Triggered if the root scroller is reached and exhausted.

#### B. `overscroll-behavior: contain`
* **Isolation Level:** Node Boundary Isolation.
* **Compositor Enforcement:** In `LayerTreeHostImpl::ScrollAnimated` or `InputHandlerProxy`, when the latched `ScrollNode` exhausts its scroll boundary, CC checks `scroll_node->overscroll_behavior`. If set to `kOverscrollBehaviorTypeContain`:
  * The ancestor traversal loop is **severed**.
  * The unused delta is zeroed out for ancestor consumption.
* **Local Overscroll:** Preserved. The element itself will still trigger local overscroll UI (e.g., Android's `EdgeEffect` glow or macOS inner-element rubber-banding, if applicable to sub-scrollers), managed via `OverscrollController`.
* **Root Protection:** Because chaining is severed, the `RootScroller` never receives the unused delta; browser navigation/refresh gestures are blocked.

#### C. `overscroll-behavior: none`
* **Isolation Level:** Absolute (Node + Local).
* **Compositor Enforcement:** Identical to `contain` regarding scroll chaining—ancestors in the `ScrollTree` are strictly isolated from unused deltas.
* **Local Overscroll:** Suppressed. The `UnusedScrollDelta` is completely discarded before reaching the `OverscrollController`. Neither ancestor scrolling nor local visual overscroll effects (glow/bounce) are executed.

---

### 4. THREAD SYNCHRONIZATION & EDGE CASES

Audit of Blink's architecture reveals three critical vectors where scroll propagation isolation requires explicit synchronization:

#### Vector 1: Main Thread Fallback (Slow-Path Scrolling)
If a scroller requires Main Thread involvement (e.g., non-composited scrolling, complex `background-attachment: fixed`, or un-promoted layers):
* CC flags the `ScrollNode` with `MainThreadScrollingReason`.
* Input events are forwarded to Blink’s `EventHandler` and `ScrollManager`.
* `ScrollManager::LogicalScroll` constructs a DOM-based scroll chain using `LayoutBox::EnclosingScrollableBox()`.
* **Isolation Check:** `ScrollManager::CanPropagate` queries the `ComputedStyle::OverscrollBehaviorX/Y()` of the current element. If `contain` or `none` is detected, the loop breaks, isolating the DOM ancestors.

#### Vector 2: Non-Scrollable Overflow Containers (The "Trap")
* **Audit Finding:** If an element has `overscroll-behavior: contain` or `none`, **and** `overflow: auto/scroll`, **but** its content does not currently overflow its client bounds (i.e., `scrollHeight <= clientHeight`):
* **Blink Behavior:** Per CSS Overscroll Behavior Module Level 1 specs, the element is still considered a *scroll container*. Blink generates a `ScrollNode` for it. When a gesture occurs inside it, it latches, consumes `0px` of delta, hits the `overscroll-behavior` boundary check, and successfully blocks propagation to the parent. *Note: If `overflow: hidden` or `visible` is used, `overscroll-behavior` has no effect and propagation continues.*

#### Vector 3: DOM Events vs. Gesture Events
* **Wheel Events (`wheel`):** `WheelEvent` DOM dispatch happens *before* or *in parallel* with default scroll actions (depending on passive listener status). `overscroll-behavior` **does not** stop the DOM `wheel` event from bubbling up the DOM tree. It only isolates the *default action* (the actual scrolling movement) handled by the `GestureScrollUpdate` pipeline.
* **Touch Events (`touchmove`):** Similar to `wheel`, raw touch events bubble normally through the DOM. Only the synthesized `GestureScroll*` events generated by the `TouchEventQueue` and `GestureProvider` are subject to `ScrollTree` propagation isolation.

---

### 5. BROWSER PROCESS HANDOFF (`DidOverscroll`)

When scroll propagation is **not** isolated (reaches the `Viewport` / `InnerViewportScrollNode` and remains unconsumed):
1. The Compositor Thread packages the leftover delta into a `DidOverscrollParams` struct.
2. This struct includes `accumulated_overscroll`, `latest_overscroll_delta`, `current_fling_velocity`, and the `OverscrollBehavior` of the root.
3. It is sent via Mojo IPC (`WidgetInputHandlerHost::DidOverscroll`) to the Browser Process.
4. If the Root Scroller itself has `overscroll-behavior: contain` or `none` (applied to `<html>` or `<body>`), the Renderer modifies the `DidOverscrollParams` flags. The Browser Process's `OverscrollController` reads this flag and aborts OS-level pull-to-refresh or history swipe navigation.

**END OF AUDIT REPORT – AGENT 332**