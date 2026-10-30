**AGENT 322 AUDIT REPORT: BLINK VIEW TIMELINE – `cover` RANGE**

### 1. Boundary Endpoints

In Blink’s implementation of CSS Scroll-Driven Animations, the `cover` timeline range represents the full cycle of a subject element intersecting the scrollport (from first pixel entering to last pixel leaving).

Assuming a standard vertical top-to-bottom scroll direction, the physical scroll offset endpoints are:

*   **Start Endpoint (`cover 0%`):** The exact scroll offset where the **start border edge** (top) of the principal box of the subject element intersects the **end edge** (bottom) of the view progress visibility range (scrollport, adjusted for `view-timeline-inset`).
    $$\text{Offset}_{\text{start}} = \text{Element}_{\text{offsetTop}} - \text{Scrollport}_{\text{height}} + \text{Inset}_{\text{end}}$$

*   **End Endpoint (`cover 100%`):** The exact scroll offset where the **end border edge** (bottom) of the principal box of the subject element intersects the **start edge** (top) of the view progress visibility range.
    $$\text{Offset}_{\text{end}} = \text{Element}_{\text{offsetTop}} + \text{Element}_{\text{height}} - \text{Inset}_{\text{start}}$$

*(Note: For horizontal or reverse writing modes/scroll directions, physical edges map to their corresponding logical block/inline flow-relative equivalents).*

---

### 2. Cover Progress Formula

Blink calculates the unconstrained progress value ($P_{\text{cover}}$) as a normalized float between `0.0` and `1.0` based on the current scroll position relative to the boundary endpoints:

$$P_{\text{cover}} = \frac{\text{ScrollOffset}_{\text{current}} - \text{Offset}_{\text{start}}}{\text{Offset}_{\text{end}} - \text{Offset}_{\text{start}}}$$

#### Expanded Geometric Formula
By substituting the physical layout metrics into the denominator (Total Cover Distance), the formula expands to:

$$P_{\text{cover}} = \frac{\text{ScrollOffset}_{\text{current}} - (\text{Element}_{\text{offsetTop}} - \text{Scrollport}_{\text{size}} + \text{Inset}_{\text{end}})}{\text{Scrollport}_{\text{size}} + \text{Element}_{\text{size}} - (\text{Inset}_{\text{start}} + \text{Inset}_{\text{end}})}$$

#### Key Variables:
*   $\text{ScrollOffset}_{\text{current}}$: Current scroll position of the scroller.
*   $\text{Scrollport}_{\text{size}}$: Client height/width of the scroll container along the relevant axis.
*   $\text{Element}_{\text{size}}$: Border-box height/width of the tracked subject element.
*   $\text{Element}_{\text{offsetTop}}$: Distance from the scroller's content origin to the element's start border edge.
*   $\text{Inset}_{\text{start}} \text{ / } \text{Inset}_{\text{end}}$: Resolved pixel values of `view-timeline-inset` (and/or `scroll-padding` if set to `auto`).

**Audit Note on Edge Cases:** If the denominator ($\text{Offset}_{\text{end}} - \text{Offset}_{\text{start}}$) resolves to `0` (e.g., an empty 0px scrollport with a 0px element, or extreme negative insets that invert the range), Blink resolves the timeline to an **inactive** state to prevent division-by-zero faults.

**END REPORT – AGENT 322**