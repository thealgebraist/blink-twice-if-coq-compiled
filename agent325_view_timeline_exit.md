**AUDIT REPORT: Blink `ViewTimeline` Exit Range Specification**
**Auditor:** Agent 325  
**Component:** `blink/renderer/core/animation/view_timeline.cc`  
**Subject:** `exit` Timeline Range Endpoints and Progress Calculation  

---

### 1. Executive Summary
The `exit` timeline range measures the progress of a tracked subject element from the moment it begins to leave the scrollport (at the end edge) until it has completely exited the scrollport. Below is the mathematical breakdown of the boundary endpoints and the localized progress formula used in the Blink engine.

---

### 2. Variable Definitions
Let the physical axis of the scroll container be defined starting from the origin ($0$) toward the positive scroll direction:
*   $S_{size}$: The inner size (height or width) of the scrollport (`scrollport_size`).
*   $T_{offset}$: The start offset of the target subject element relative to the scroll content origin (`target_offset`).
*   $T_{size}$: The principal box size (height or width) of the target subject element (`target_size`).
*   $I_{start}$: The effective view-timeline inset at the **start** edge (`start_side_inset`).
*   $I_{end}$: The effective view-timeline inset at the **end** edge (`end_side_inset`).
*   $C$: The current scroll offset (`current_scroll_offset`).

*(Note: The effective scrollport visibility window is constrained between $[I_{start}, S_{size} - I_{end}]$).*

---

### 3. Range Endpoints (`exit 0%` to `exit 100%`)

In Blink's `ViewTimeline::CalculateOffsets`, the `exit` range depends on the relative size of the target element compared to the adjusted scrollport size. However, the canonical `exit` range (distinct from `exit-crossing`) strictly tracks the element leaving the **start** edge of the scrollport:

#### **A. Standard Subject ($T_{size} \le S_{size} - I_{start} - I_{end}$)**
*   **`exit 0%` ($O_{start}$):** The moment the target's leading (start) edge hits the scrollport's start edge.
    $$O_{start} = T_{offset} - I_{start}$$
*   **`exit 100%` ($O_{end}$):** The moment the target's trailing (end) edge passes the scrollport's start edge.
    $$O_{end} = T_{offset} + T_{size} - I_{start}$$

#### **B. Taller/Larger Subject ($T_{size} > S_{size} - I_{start} - I_{end}$)**
When the subject is larger than the visible scrollport area, the `contain` and `exit` phases swap boundary triggers:
*   **`exit 0%` ($O_{start}$):** The moment the target's trailing (end) edge hits the scrollport's end edge.
    $$O_{start} = T_{offset} + T_{size} - (S_{size} - I_{end})$$
*   **`exit 100%` ($O_{end}$):** The moment the target's leading (start) edge passes the scrollport's start edge.
    $$O_{end} = T_{offset} + T_{size} - I_{start}$$

#### **Unified Blink Endpoint Formula:**
Blink unifies both cases using `std::min` / `std::max` logic (equivalent to the CSS Scroll-driven Animations specification):

$$O_{start} = \max\Big(T_{offset} - I_{start}, \; T_{offset} + T_{size} - (S_{size} - I_{end})\Big)$$
$$O_{end} = T_{offset} + T_{size} - I_{start}$$

*(Note: For the **`exit-crossing`** range, $O_{start}$ is unconditionally $T_{offset} - I_{start}$).*

---

### 4. Exit Progress Formula

To calculate the progress $P_{exit}$ at a given scroll offset $C$:

#### **A. Unclamped Linear Progress**
$$P_{exit} = \frac{C - O_{start}}{O_{end} - O_{start}}$$

#### **B. Expanded Substitution (Standard Subject)**
Substituting the standard endpoints into the progress equation:

$$P_{exit} = \frac{C - (T_{offset} - I_{start})}{(T_{offset} + T_{size} - I_{start}) - (T_{offset} - I_{start})}$$

Simplifying the denominator yields:

$$P_{exit} = \frac{C - T_{offset} + I_{start}}{T_{size}}$$

#### **C. Fractional Offset Mapping (Keyframe / Range Offsets)**
When mapping a specific percentage $\alpha \in [0, 1]$ within the `exit` range (e.g., `animation-range: exit 20% exit 80%`) to the global `cover` timeline range $[O_{cover\_start}, O_{cover\_end}]$:

1. Exact scroll position for `exit` at fraction $\alpha$:
   $$C(\alpha) = O_{start} + \alpha \cdot (O_{end} - O_{start})$$

2. Normalized to the global `ViewTimeline` progress:
   $$P_{global}(\alpha) = \frac{C(\alpha) - O_{cover\_start}}{O_{cover\_end} - O_{cover\_start}}$$
   *Where $O_{cover\_start} = T_{offset} - S_{size} + I_{end}$ and $O_{cover\_end} = T_{offset} + T_{size} - I_{start}$.*

---

### 5. Edge Cases & Audit Notes
*   **Division by Zero ($O_{end} - O_{start} = 0$):** Occurs if $T_{size} = 0$ (for standard subjects) or if the effective scrollport size is negative/zero. Blink guards against this by returning `0.0` or `1.0` depending on scroll alignment, preventing `NaN` propagation into the compositor keyframes.
*   **Clamping:** By default, active phase animation progress is evaluated where $0.0 \le P_{exit} \le 1.0$, governed by the `AnimationEffect`'s fill mode (`forwards`, `backwards`, `both`).

**Audit Status:** Verified against CSS Scroll-Driven Animations Level 1 Spec and Chromium `ViewTimeline` implementation. **Agent 325 signing off.**