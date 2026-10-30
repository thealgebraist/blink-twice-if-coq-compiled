**AUDIT REPORT: Blink LayoutNG Grid — Subgrid Track Span Matching**
**Auditor:** Agent 385
**Target Component:** `third_party/blink/renderer/core/layout/grid/` (Specifically `GridLayoutSubgrid`, `GridTrackCollection`, and `GridItemData`)
**Subject:** Track Span Preservation and Boundary Clipping in CSS Subgrid (`grid-template-columns: subgrid` / `grid-template-rows: subgrid`)

---

### 1. Executive Summary
This audit details the internal mechanisms by which the Blink rendering engine resolves, preserves, and clips grid track spans for subgridded axes within the LayoutNG architecture. Per the CSS Grid Layout Module Level 2 specification, a subgrid does not define its own implicit grid tracks along a subgridded axis; rather, it borrows the tracks spanned by its own grid item box in the parent grid. Consequently, descendant grid items placed within the subgrid must have their spans preserved relative to the subgrid's local coordinate space, strictly clamped to the subgrid’s explicit bounds, and translated accurately into the ancestor grid's track sizing algorithm.

---

### 2. Track Span Preservation

Track span preservation refers to the mechanism by which a subgrid item's start/end lines (or explicit spans) are maintained across nested grid contexts so they can participate directly in the ancestor grid's `GridSizingTree` and `GridTrackSizingAlgorithm`.

#### 2.1. Subgrid Span Establishment
Before a subgrid can resolve its children's spans, its own span within the parent grid must be resolved and made definite.
* **Parent Resolution:** During the parent grid's placement phase (`GridLineResolver`), the subgrid item's `GridSpan` is resolved into a definite zero-indexed `[start_line, end_line)` range within the parent's `GridTrackCollection`.
* **Local Explicit Grid Synthesis:** The size of the subgrid’s local explicit grid in the subgridded dimension is strictly defined by the cardinality of its resolved parent span:
  $$\text{Subgrid Explicit Tracks} = \text{Parent End Line} - \text{Parent Start Line}$$
* **No Implicit Tracks:** Blink enforces a hard invariant on subgridded axes: `implicit_grid_tracks_` is locked to `0`. All track indices within the subgrid are strictly bounded by `[0, subgrid_span_size]`.

#### 2.2. Coordinate Space Translation (Offset Mapping)
To preserve a subgrid item's span during ancestor track sizing (especially for intrinsic sizing phases like `ResolveIntrinsicTrackSizes`), Blink maps the item's local span into the ancestor's coordinate space during `GridSizingTree` construction:
* **Local Resolution:** A child of the subgrid resolves its `grid-row` / `grid-column` properties using `GridLineResolver`, referencing the subgrid’s synthesized explicit line count and combining `subgrid` line name sets inherited from the parent with local line names declared on the subgrid (`subgrid [line-name]`).
* **Translation Formula:** Once the item's local span $[S_{\text{local}}, E_{\text{local}})$ is determined (and clamped, see Section 3), Blink preserves the span's geometry by applying the subgrid's offset relative to the parent grid:
  $$S_{\text{parent}} = S_{\text{local}} + \text{Subgrid}_{S_{\text{parent}}}$$
  $$E_{\text{parent}} = E_{\text{local}} + \text{Subgrid}_{S_{\text{parent}}}$$
* **Multi-level Nesting:** In deeply nested subgrids, this offset accumulation is transitive. `BuildGridSizingSubtree` accumulates offsets down the tree so that a leaf grid item's `GridSpan` can be directly indexed into the root grid's `GridSizingTrackCollection`.

#### 2.3. Margin, Border, and Padding (MBP) Adjustment
While the topological track span is preserved 1:1, the *physical* contribution of a subgrid item to the ancestor tracks at the boundary edges of the subgrid must account for the subgrid's own box model:
* Blink injects the subgrid's `border`, `padding`, and `margin` (along with the difference between parent `gap` and subgrid `gap`) as an extra margin contribution (`subgrid_margin_border_padding`) onto subgrid items whose spans touch the first ($S_{\text{local}} = 0$) or last ($E_{\text{local}} = N$) tracks of the subgrid.

---

### 3. Boundary Clipping (Clamping)

Because a subgrid cannot generate implicit tracks in a subgridded dimension, any subgrid item whose placement resolves outside the subgrid's borrowed track range must undergo boundary clipping (clamping) per CSS Grid 2 § 2.3.

#### 3.1. Trigger Conditions for Clipping
In Blink's `GridLineResolver` and placement normalization routines, clipping is triggered when a subgrid item resolves to:
1. **Negative Indices / Pre-Explicit Lines:** E.g., `grid-column: -10` (exceeding total tracks) or referencing a nonexistent line name, which normally falls back to the implicit grid before line 1.
2. **Post-Explicit Overflow:** E.g., `grid-column: 10 / 15` within a subgrid that only spans 4 parent tracks.
3. **Oversized Explicit Spans:** E.g., `grid-column: auto / span 8` inside a 4-track subgrid.
4. **Auto-Placement Overflow:** When the `GridPlacement` cursor advances past the final track of the subgrid.

#### 3.2. Blink's Clamping Algorithm
Let $N$ be the number of tracks spanned by the subgrid in the parent grid (meaning valid zero-based line indices are $[0, N]$). When a child item's raw untranslated span $[S_{\text{raw}}, E_{\text{raw}})$ is computed, Blink applies the following clamping logic to guarantee a valid `GridSpan::TranslatedDefiniteGridSpan`:

1. **Span Truncation (If Both Lines are Indefinite/Auto + Span):**
   If an item is auto-placed with a span $K > N$, the span $K$ is truncated to $N$ prior to placement so the item fits between line $0$ and line $N$.

2. **Upper and Lower Bound Clamping (Definite Lines):**
   Both start and end lines are independently clamped to the valid line index boundary $[0, N]$:
   $$S_{\text{clamped}} = \max(0, \min(S_{\text{raw}}, N))$$
   $$E_{\text{clamped}} = \max(0, \min(E_{\text{raw}}, N))$$

3. **Degenerate Span Prevention (Single-Track Collapse):**
   In CSS Grid, a grid item must span at least one track ($E > S$). If both $S_{\text{raw}}$ and $E_{\text{raw}}$ were outside the subgrid on the same side, clamping both to $[0, N]$ would result in a zero-width span ($0/0$ or $N/N$). Blink enforces a minimum span of 1 track at the extreme boundary:
   * **Underflow Collapse ($S_{\text{raw}} < E_{\text{raw}} \le 0$):**
     Clamped to the *first* track of the subgrid:
     $$[S_{\text{final}}, E_{\text{final}}) = [0, 1)$$
   * **Overflow Collapse ($N \le S_{\text{raw}} < E_{\text{raw}}$):**
     Clamped to the *last* track of the subgrid:
     $$[S_{\text{final}}, E_{\text{final}}) = [N - 1, N)$$
   * **Partial Overlap:**
     If $S_{\text{raw}} < 0$ and $0 < E_{\text{raw}} \le N$, the span is clipped at the start edge: $[0, E_{\text{raw}})$.
     If $0 \le S_{\text{raw}} < N$ and $E_{\text{raw}} > N$, the span is clipped at the end edge: $[S_{\text{raw}}, N)$.

#### 3.3. Auto-Placement Cursor Clamping
When `GridPlacement` runs on a subgrid:
* If the subgrid's `grid-auto-flow` axis is subgridded, the cursor places items sequentially up to track $N-1$.
* If an item cannot fit in the remaining tracks of the current row/column and there are no further tracks in the secondary axis (because the secondary axis is *also* subgridded and exhausted), the cursor does not create a new implicit row/column. Instead, it clamps the placement into the final available track $[N-1, N)$, resulting in intentional item overlap at the trailing edge of the subgrid.

---

### 4. Edge Cases & Audit Verification Points

| Scenario | Blink LayoutNG Behavior | Verification Status |
| :--- | :--- | :--- |
| **Nested Subgrid Clipping** | Parent Grid (10 tracks) $\rightarrow$ Subgrid A (spans 2..8, $N_A=6$) $\rightarrow$ Subgrid B (placed at local `1 / 10` in A). Subgrid B is clipped to `[0, 6)` in A, inheriting 6 tracks. | **PASS**: Clamping occurs top-down during placement before child subgrids resolve their own track counts. |
| **Subgrid Item with `span > N`** | Item has `grid-column: span 10` inside a 3-track subgrid. | **PASS**: Clamped to `[0, 3)`. Does not trigger out-of-bounds vector access in `GridLayoutTrackCollection::SetRange`. |
| **Named Line Resolution Beyond Bounds** | Parent defines `[a]` at line 1, `[b]` at line 9. Subgrid spans lines `3 / 6`. Child requests `grid-column: a / b`. | **PASS**: Line resolver restricts named line lookup strictly to the slice of parent lines `[3, 6]`. `[a]` and `[b]` are treated as not found, falling back to implicit/clamped edge behavior. |
| **Writing Mode / Directionality Flip** | Parent is `ltr`, Subgrid is `rtl`. Child placed at `1 / 2` in subgrid. | **PASS**: Local span `[0, 1)` is clamped in the subgrid's logical coordinate space, then inverted via `GridSpan::Translate` when mapped to the parent's `ltr` track collection (`[N - E_local, N - S_local)`). |

**Conclusion:** Blink's `LayoutNGGrid` implementation maintains strict memory and layout safety for subgrid track spans. By forcing clamping during the `GridPlacement` phase prior to `GridSizingTree` offset translation, no subgrid item can ever mutate or request tracks outside the subgrid's allocated parent span.