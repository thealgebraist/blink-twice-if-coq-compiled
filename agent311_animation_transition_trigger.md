**AUDIT LOG: SYSTEM_BLINK // AGENT 311**  
**SUBJECT:** CSS Transition Initiation Conditions (Blink Rendering Engine)  
**STATUS:** ACTIVE AUDIT  

As Agent 311, I have inspected the style and animation pipelines within the Blink rendering engine. A CSS transition will not initiate merely upon a property modification. It requires a strict sequence of states and conditions to be met during the Style Recalculation and Lifecycle Update phases.

Below are the detailed, mandatory conditions required for Blink to trigger a CSS transition:

### 1. Existence of "Before-Change" and "After-Change" Styles
For a transition to occur, Blink must be able to compare two distinct style states across two separate style update cycles (frames):
*   **Condition 1A (Established Baseline):** The element must have an existing **Before-Change Style** (the computed style from the previous lifecycle update). If an element is newly inserted into the DOM and styled in the same frame, no transition will occur because no prior baseline exists.
*   **Condition 1B (Delta Detection):** During the current style recalculation phase, the newly computed **After-Change Style** must yield a Computed Value for the target property that is mathematically or logically distinct from the Before-Change Style.

### 2. Box Generation and Layout Presence
*   **Condition 2A (Render Tree Inclusion):** The target element must generate a layout box (i.e., `display` cannot be `none` in either the Before-Change or After-Change state, unless specifically utilizing the `transition-behavior: allow-discrete` flag alongside `@starting-style` in modern Blink implementations). 
*   **Condition 2B (DOM Attachment):** The element must be actively attached to the Document tree.

### 3. Valid Transition Configuration
The **After-Change Style** of the element must possess valid `transition-*` properties:
*   **Condition 3A (Property Matching):** `transition-property` must explicitly name the mutated property, or be set to `all`.
*   **Condition 3B (Positive Timeline):** The combined temporal value of `transition-duration` and `transition-delay` must be greater than `0s` (`duration + delay > 0`). If `duration` is `0s` and `delay` is `0s` (or negative), the engine skips instantiation of the animation player and snaps to the final state.
*   **Condition 3C (Interpolability):** The target property must be defined in Blink's CSS properties registry as *interpolable* (or *discrete* if `transition-behavior: allow-discrete` is active). Furthermore, the specific values must be interpolable (e.g., transitioning `height` from `100px` to `auto` will fail initiation unless `calc-size()` or `interpolate-size` is utilized, as `auto` cannot be standardly interpolated).

### 4. Pipeline & Preemption Clearances
*   **Condition 4A (No CSS Animation Override):** The target property must not be currently controlled by an active `@keyframes` CSS Animation, which takes precedence in the Blink cascade/animation stack, suppressing the transition trigger.
*   **Condition 4B (Style Flushing):** If the property was mutated via JavaScript, the Before-Change and After-Change states must not be batched into the same render frame. If mutated sequentially in JS, a **forced synchronous layout (style flush)**—such as reading `element.offsetTop` or `getComputedStyle(element)`—must occur between mutations to force Blink to register the Before-Change style before applying the After-Change style.

---

**SUMMARY OF EXECUTION:**  
If Conditions **1 through 4** evaluate to `TRUE` during `DocumentLifecycle::kInStyleRecalc`, Blink’s `CSSAnimations::CalculateTransitionUpdate` method will instantiate a new `Transition` object, dispatch a `transitionrun` event, and hand the interpolation off to the Main Thread or Compositor Thread (if the property is compositor-compatible, e.g., `transform` or `opacity`).

**END OF REPORT // AGENT 311**