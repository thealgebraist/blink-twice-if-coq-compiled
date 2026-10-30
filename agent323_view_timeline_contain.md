**AUDIT REPORT: Blink `ViewTimeline` – `contain` Range Specification**
**Auditor:** Agent 323
**Component:** `third_party/blink/renderer/core/animation/view_timeline.cc`
**Specification:** CSS Scroll-Driven Animations (Level 1)

---

### 1. Executive Summary
The `contain` range of a `ViewTimeline` represents the scroll interval during which the principal box (subject) is **entirely contained** within the scrollport (adjusted by `view-timeline-inset`). If the subject is larger than the scrollport along the relevant axis, the `contain` range represents the interval during which the subject **entirely covers** the scrollport.

### 2. Core Variables
Let the following variables be defined along the relevant scroll axis (Block or Inline) in scroll coordinates:
*   $V$: Size of the scrollport (adjusted by `view-timeline-inset`).
*   $S$: Size of the target subject's border box.
*   $P_{offset}$: Scroll offset of the subject's start edge relative to the scroll container's origin.
*   $I_{start}$: Effective start inset (from `view-timeline-inset`, auto/scroll-padding).
*   $I_{end}$: Effective end inset.

### 3. Reference Positions
Before applying the `contain` bounds, Blink calculates the two fundamental intersection offsets where the subject's edges align with the scrollport's opposite edges:

1.  **Entry Complete ($C_{entry}$):** The scroll offset where the subject's *end* edge aligns with the scrollport's *end* edge.
    $$C_{entry} = P_{offset} - V + S + I_{end}$$

2.  **Exit Start ($C_{exit}$):** The scroll offset where the subject's *start* edge aligns with the scrollport's *start* edge.
    $$C_{exit} = P_{offset} - I_{start}$$

---

### 4. `contain` Bounds (0% and 100%)
Because a subject can be either smaller or larger than the scrollport, the `contain` bounds use `std::min` and `std::max` to prevent inverted ranges.

*   **`contain 0%` ($B_{start}$):**
    $$B_{start} = \min(C_{entry}, C_{exit})$$
*   **`contain 100%` ($B_{end}$):**
    $$B_{end} = \max(C_{entry}, C_{exit})$$

#### Behavioral Branching:
*   **Case A: Subject Smaller than Scrollport ($S < V$)**
    *   $B_{start} = C_{entry}$ (Subject finishes entering).
    *   $B_{end} = C_{exit}$ (Subject starts exiting).
*   **Case B: Subject Larger than Scrollport ($S > V$)**
    *   $B_{start} = C_{exit}$ (Subject's start edge hits scrollport start; scrollport is now fully covered).
    *   $B_{end} = C_{entry}$ (Subject's end edge hits scrollport end; subject is about to uncover the scrollport).
*   **Case C: Subject Equals Scrollport ($S = V$)**
    *   $B_{start} = B_{end}$. Range duration is $0\text{px}$.

---

### 5. `contain` Progress Formula
For a given current scroll offset $X$:

$$\text{Progress}_{contain}(X) = \frac{X - B_{start}}{B_{end} - B_{start}}$$

#### Expanded Formula:
$$\text{Progress}_{contain}(X) = \frac{X - \min(P_{offset} - V + S + I_{end}, \; P_{offset} - I_{start})}{\lvert V - S - I_{start} - I_{end} \rvert}$$

---

### 6. Edge Cases & Clamping Audit
1.  **Zero-Length Range ($B_{start} == B_{end}$):**
    When $S = V - I_{start} - I_{end}$, the denominator is $0$. Blink handles division by zero by snapping progress directly from $0.0$ (when $X < B_{start}$) to $1.0$ (when $X \ge B_{end}$) based on timeline phase logic (`kPhaseBefore` vs `kPhaseAfter`).
2.  **Active Range Clamping:**
    When evaluating an animation attached strictly to `animation-range: contain`, the progress is clamped to $[0.0, 1.0]$ during the active phase, governed by the animation's `fill-mode` (`forwards`, `backwards`, `both`, `none`) outside $[B_{start}, B_{end}]$.

**Audit Status:** Verified compliant with W3C CSS Scroll-Driven Animations specification. **Agent 323 signing off.**