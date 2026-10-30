**AUDIT REPORT: Blink Table `<tfoot>` Pagination Space Reservation**
**Agent ID:** 362
**Subsystem:** Blink LayoutEngine (LayoutNG / Table Fragmentation)
**Target:** `NGTableLayoutAlgorithm` & `NGConstraintSpace`

---

### 1. Executive Summary
In Blink’s LayoutNG architecture, repeating a `<tfoot>` across paginated media (print, `multicol`) requires the table layout algorithm to proactively reserve vertical space (block-size) at the bottom of every fragmentainer (page/column). This audit details the exact mechanism by which Blink calculates, reserves, and releases this bottom space to prevent `<tbody>` content from colliding with the repeating footer.

---

### 2. Pre-Conditions for Reservation
Before space is reserved, `NGTableLayoutAlgorithm` validates if the `<tfoot>` is eligible for repetition. Space is **only** reserved if all the following criteria are met:
1. `ConstraintSpace().HasBlockFragmentation()` is `true`.
2. `ConstraintSpace().HasKnownFragmentainerBlockSize()` is `true`.
3. **The Decision Heuristic:** The `<tfoot>` block-size (plus any repeating `<thead>` block-size) must not exceed **25% of the fragmentainer's total block-size** (Blink limits captions/headers/footers to avoid infinite pagination loops). 

*Note: If the CSS property `break-inside: avoid` is not implicitly or explicitly respected due to size constraints, the footer drops to the very end of the table and no bottom reservation occurs on intermediate pages.*

---

### 3. The Reservation Mechanism

#### Phase A: Pre-Layout Measurement
Before laying out the `<tbody>` or determining fragment breaks, `NGTableLayoutAlgorithm` measures the `<tfoot>` in an unfragmented constraint space to determine its natural `LayoutUnit` block-size.
* **Variable:** `tfoot_block_size` is cached.

#### Phase B: Constraint Space Modification
As the table algorithm iterates through child sections (`<tbody>`), it sets up a `NGConstraintSpaceBuilder` for each child. To reserve the bottom space, it modifies the **Fragmentainer Space Available**.

Instead of physically placing the `<tfoot>` at the bottom and laying out backwards, Blink **artificially shrinks the fragmentainer** seen by the `<tbody>`:

```cpp
// Conceptual representation inside NGTableLayoutAlgorithm::Layout()
LayoutUnit reserved_space = tfoot_block_size + border_spacing;
builder.SetFragmentainerSpaceAtBfcStart(
    fragmentainer_space_at_bfc_start - reserved_space);
```

* **`FragmentainerBlockSize` vs `FragmentainerSpaceAvailable`:** The algorithm deducts the `<tfoot>` height from the `FragmentainerOffset` allowance. 
* **Effect on `<tbody>`:** When a `<tr>` inside the `<tbody>` is being laid out, it checks if its block-size exceeds the remaining fragmentainer space. Because that space was reduced by `tfoot_block_size`, the `<tr>` will trigger an early fragmentation break (`kOutOfFragmentainerSpace`) exactly at the top boundary of where the `<tfoot>` needs to go.

---

### 4. Handling the Final Fragment (Space Release)
A critical edge case in bottom reservation is the **final page/column** of the table. The `<tfoot>` must sit immediately below the final `<tr>` of the `<tbody>`, rather than being pushed to the very bottom of the page.

1. **Detection:** When the `<tbody>` completes its layout and returns a `NGLayoutResult` with no `BreakToken` (meaning all rows are exhausted), the algorithm knows it is on the final fragment.
2. **Placement:** The reserved space at the bottom of the fragmentainer is instantly consumed by appending the final instance of the `<tfoot>` directly after the `<tbody>`'s end offset.
3. **Overflow Check:** Because the space was already deducted from the `<tbody>`'s available space, the `<tfoot>` is guaranteed to fit in the remaining fragmentainer space without causing an orphan page break.

---

### 5. Identified Edge Cases & Anomalies (Audit Findings)

* **Border-Spacing & Collapsed Borders:**
  * *Finding:* The reservation calculation must include `border-spacing` (for `border-collapse: separate`) or the thickest potential collapsed bottom/top border (for `border-collapse: collapse`). 
  * *Status:* Blink currently reserves the `<tfoot>` size plus one standard `v_spacing` unit. Dynamic collapsed borders on fragmented rows occasionally cause a 1px–2px subpixel overflow if the `<tbody>` row has a vastly thicker border than the `<tfoot>`.
* **Nested Tables:**
  * *Finding:* If a parent table and a child table both have repeating `<tfoot>` elements, the space reservation is **additive**. The inner `NGConstraintSpace` inherits the already-shrunk fragmentainer space and shrinks it further.
* **Orphaned Headers with Reserved Footers:**
  * *Finding:* If a table starts near the bottom of a page, Blink requires enough room for the `<thead>`, at least one `<tr>`, **and** the reserved `<tfoot>` space. If `AvailableSpace < (thead + tr_1 + tfoot)`, the entire table pushes to the next fragmentainer.

---
**End of Report.** 
*Agent 362 standing by for further subsystem directives.*