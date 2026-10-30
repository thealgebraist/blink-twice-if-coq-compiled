**AUDIT REPORT: Blink CSS Subgrid Line Name Inheritance, Lookup, and Indexing**
**Auditor:** Agent 386
**Target Component:** `third_party/blink/renderer/core/layout/grid/`

---

### 1. Executive Summary
In Blink’s LayoutNG Grid implementation (`GridLayoutAlgorithm`), a subgrid does not define its own independent track sizing on a subgridded axis; instead, it adopts a slice of its parent grid’s tracks. Consequently, line name resolution for grid items inside a subgrid requires merging **inherited line names** from the parent grid (and any intermediate ancestor subgrids) with **locally declared line names** (`grid-template-columns/rows: subgrid [line-name] ...`). 

This audit details the mechanics of index translation, line name inheritance, and item placement lookup within Blink's rendering engine.

---

### 2. Coordinate Space & Index Translation

To understand line name lookup, one must first understand how Blink maps indices between a parent grid and a subgrid. 

* **Parent Absolute Grid Space:** 0-based index starting from the parent’s first explicit or negative-implicit line.
* **Subgrid Local Explicit Space:** 0-based index relative to the subgrid’s own start edge.

#### The Span Offset
When a subgrid is placed on a parent grid, its position is resolved into a `GridSpan` (`start_line`, `end_line`). 
* Let $S_{start}$ be the subgrid's resolved `start_line` in the parent's coordinate space.
* Let $S_{end}$ be the subgrid's resolved `end_line` in the parent's coordinate space.
* The total number of lines inherited by the subgrid is $(S_{end} - S_{start}) + 1$.

**Index Translation Formula:**
For any parent line index $I_{parent}$ where $S_{start} \le I_{parent} \le S_{end}$, the corresponding subgrid local explicit line index $I_{local}$ is:
$$I_{local} = I_{parent} - S_{start}$$

*Audit Note:* Subgrids **cannot** generate implicit tracks on a subgridded axis. Any grid item placed outside the $[0, S_{end} - S_{start}]$ local range is clamped to the subgrid's explicit boundaries during track sizing, though line resolution itself must account for out-of-bounds integer lookups before clamping.

---

### 3. Line Name Inheritance & Merging

Line name collection is managed during the grid sizing tree construction phase via `GridLineResolver`. When a subgrid is initialized, its `GridLineResolver` is constructed by passing the parent’s `GridLineResolver` alongside the subgrid’s `ComputedStyle` and its `GridSpan` within the parent.

Blink merges line names from four distinct sources for a subgridded axis:

#### A. Inherited Explicit & Implicit Line Names (From Ancestors)
The subgrid queries the parent’s resolved line name map for the range $[S_{start}, S_{end}]$.
* If the parent has a line name `[foo]` at $I_{parent}$, and $S_{start} \le I_{parent} \le S_{end}$, `[foo]` is registered in the subgrid's lookup map at index $I_{parent} - S_{start}$.
* **Implicit Grid Area Names:** If the parent defines `grid-template-areas` (e.g., `"header header"`), the parent implicitly generates `header-start` and `header-end` line names. If these lines fall within $[S_{start}, S_{end}]$, the subgrid inherits them as standard explicit line names at the translated local indices.

#### B. Local Subgrid Line Names
The subgrid's own `ComputedStyle` may specify line names inside the `subgrid` syntax:
`grid-template-columns: subgrid [local-a] repeat(auto-fill, [local-b]) [local-c];`
* **`NamedGridLinesMap`:** Blink parses these into standard and auto-repeat line maps.
* **`auto-fill` Expansion:** Unlike standalone grids where `auto-fill` calculates repetitions based on available container size, a subgrid’s `auto-fill` count is strictly deterministic based on the number of inherited lines:
  $$\text{Repetitions} = \left\lfloor \frac{(S_{end} - S_{start} + 1) - \text{NonRepeatLines}}{\text{RepeatTrackListLength}} \right\rfloor$$
* Excess local line names defined beyond $(S_{end} - S_{start})$ are ignored/truncated by Blink, as subgrids cannot force the parent to grow tracks via local line definitions.

#### C. Subgrid's Own `grid-template-areas`
A subgrid can define its own `grid-template-areas`. These generate implicit `<area>-start` and `<area>-end` line names directly in the subgrid's local coordinate space $[0, S_{end} - S_{start}]$.

---

### 4. Line Name Lookup & Resolution Algorithm

When a grid item inside the subgrid specifies a named line (e.g., `grid-column-start: foo 2` or `grid-column-start: -1 foo`), `GridLineResolver::LookUpLine` executes the following sequence:

#### Step 1: Unified Index Set Generation
Instead of mutating the `ComputedStyle` (which is immutable and shared), Blink's `GridLineResolver` dynamically constructs or queries a combined sorted list of local indices for the target `AtomicString` (line name).

For a given `line_name`:
1. **Query Ancestor Chain:** Recursively fetch indices for `line_name` from the parent `GridLineResolver`. Filter for indices within $[S_{start}, S_{end}]$ and subtract $S_{start}$ from each.
2. **Query Local Explicit:** Fetch indices from the subgrid's own `subgrid [...]` list (including expanded `repeat()` blocks).
3. **Query Local Areas:** Check if `line_name` matches a `-start` or `-end` of the subgrid’s local `grid-template-areas`.
4. **Merge & Deduplicate:** Combine all resolved local indices into a single, strictly increasing `WTF::Vector<wtf_size_t>` (e.g., `[0, 2, 5]`). If both the parent and the subgrid name the *same* physical line `[foo]`, it is deduplicated so it only counts as a single occurrence of `[foo]`.

#### Step 2: N-th Occurrence Indexing
Given a placement `grid-column-start: <ident> <integer>` (where `<integer>` defaults to `1` if omitted):
* **Positive Integer ($N > 0$):** Blink indexes into the merged vector from the start: `merged_indices[N - 1]`.
* **Negative Integer ($N < 0$):** Blink indexes into the merged vector from the end: `merged_indices[merged_indices.size() + N]`.

#### Step 3: Fallback / Out-of-Bounds Handling
Per CSS Grid Layout Module Level 2:
* If the `line_name` does not exist in the merged vector, or if $|N|$ exceeds `merged_indices.size()`, the lookup overflows the explicit subgrid.
* In a standard grid, this creates implicit tracks (assumed to all have the requested line name).
* In a **subgrid**, because there is no implicit grid on a subgridded axis, out-of-bounds named line lookups resolve to the outer edges of the subgrid (clamped during `GridPlacement` to local index `0` or `S_end - S_start`).

---

### 5. Edge Cases & Audit Findings in Blink

1. **Nested Subgrids (Multi-level Inheritance):**
   If Subgrid B is inside Subgrid A, which is inside Root Grid R:
   $$I_{local\_B} = I_{local\_A} - S_{A\_to\_B\_start} = (I_{root} - S_{R\_to\_A\_start}) - S_{A\_to\_B\_start}$$
   Blink handles this by chaining `GridLineResolver` pointers or accumulating the offset in `GridSizingTree`. The deduplication step at each level ensures that if Root, A, and B all name the same line `[x]`, an item in B asking for `x 2` will not erroneously match the same line three times.

2. **Subgrid Orientation Swap (`writing-mode`):**
   If the parent grid is `horizontal-tb` and the subgrid is `vertical-rl`:
   * The subgrid's **columns** inherit from the parent's **rows**.
   * If the inline/block direction is inverted (e.g., `rtl` or `vertical-rl`), the subgrid's line `0` corresponds to the parent's $S_{end}$, not $S_{start}$.
   * **Inverted Translation Formula:** 
     $$I_{local} = S_{end} - I_{parent}$$
   * **Area Name Flipping:** When directions are inverted, a parent's implicit `area-start` (which is physically at $S_{start}$) ends up at the subgrid's local end edge. However, per CSS spec, the *string name* `area-start` is inherited verbatim, even though it now sits at the local `end` of the area in the subgrid's coordinate system. Blink correctly resolves explicit names verbatim and resolves local `grid-area: area` placements by sorting the resulting start/end indices if `start > end`.

---
**End of Audit.**