**AUDIT REPORT: Blink `ViewTimeline` Entry Range Specification**  
**Auditor:** Agent 324  
**Target:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/animation/view_timeline.cc`)  
**Subject:** `entry` Timeline Range Progress Formula and Endpoints  

---

### 1. Executive Summary
The `entry` range of a CSS `ViewTimeline` measures the phase during which the principal box of the subject element is entering the scrollport (the view progress visibility range). It begins the moment the leading edge of the subject intersects the trailing edge of the scrollport (`0%`) and concludes when the sujeto is either fully contained within the scrollport or has completely filled it (`100%`).

---

### 2. Definitions & Variables
Within Blink's layout and animation calculations along the relevant scroll axis (block or inline):

*   $S_{size}$ : **Scrollport Size**. The client size of the scroll container, adjusted by `view-timeline-inset` ($Inset_{start}$ and $Inset_{end}$).
    $$S_{size} = \text{ClientSize} - Inset_{start} - Inset_{end}$$
*   $T_{size}$ : **Target (Subject) Size**. The bounding box size of the tracked element along the scroll axis.
*   $T_{pos}$ : **Target Position**. The scroll offset of the subject's leading border edge relative to the scroll container's scroll origin.
*   $O_{curr}$ : **Current Scroll Offset** of the scroll container.

---

### 3. Endpoint Calculations (Scroll Offsets)

The `entry` range is bounded by two specific scroll offsets: $O_{start}$ (`entry 0%`) and $O_{end}$ (`entry 100%`).

#### **Start Endpoint (`entry 0%`)**
Occurs when the **leading edge** of the subject intersects the **end edge** of the effective scrollport.
$$O_{start} = T_{pos} - S_{size} + Inset_{end}$$
*(Note: If evaluating purely within the inset-adjusted coordinate space, this simplifies to $T_{pos} - S_{size}$).*

#### **End Endpoint (`entry 100%`)**
Occurs when the subject has fully entered the scrollport. However, if the subject is larger than the scrollport ($T_{size} > S_{size}$), it cannot be "fully contained" before its leading edge exits the start edge of the scrollport. Therefore, Blink clamps this using a `min` function:

*   **Case A ($T_{size} \le S_{size}$):** Trailing edge of subject intersects the end edge of the scrollport.
*   **Case B ($T_{size} > S_{size}$):** Leading edge of subject intersects the start edge of the scrollport.

$$O_{end} = O_{start} + \min(T_{size}, S_{size})$$

Expanding this into absolute scroll coordinates:
$$O_{end} = T_{pos} - S_{size} + Inset_{end} + \min(T_{size}, S_{size})$$

---

### 4. Entry Progress Formula

The total scroll distance ($D_{entry}$) over which the `entry` range occurs is:
$$D_{entry} = O_{end} - O_{start} = \min(T_{size}, S_{size})$$

The raw fractional progress ($P_{entry}$) at any given scroll offset ($O_{curr}$) is calculated as:

$$P_{entry} = \frac{O_{curr} - O_{start}}{O_{end} - O_{start}}$$

Substituting the endpoints into the formula yields the unified Blink calculation:

$$P_{entry} = \frac{O_{curr} - (T_{pos} - S_{size} + Inset_{end})}{\min(T_{size}, S_{size})}$$

---

### 5. Edge Cases & Engine Constraints
1.  **Zero-Division Guard:** If $\min(T_{size}, S_{size}) == 0$ (e.g., an empty target element with `height: 0` or a collapsed scrollport), $O_{start} == O_{end}$. Blink prevents `NaN` propagation by resolving progress to `0.0` prior to the offset and `1.0` after the offset.
2.  **Alternative Ranges Comparison:** 
    *   Unlike `entry`, the `entry-crossing` range ignores the $\min()$ clamp and strictly uses $T_{size}$ as the denominator: $O_{end} = O_{start} + T_{size}$.

**Audit Status:** Verified against W3C Scroll-Driven Animations Level 1 Specification and Blink implementation. **Agent 324 out.**