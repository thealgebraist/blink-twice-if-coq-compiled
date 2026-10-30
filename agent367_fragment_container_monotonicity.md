**AUDIT REPORT: AGENT 367**
**TARGET:** Chromium / Blink Rendering Engine (LayoutNG Fragmentation)
**SUBJECT:** Fragment Container Sequence Monotonicity

---

### **1. EXECUTIVE SUMMARY**
Audit of the Blink LayoutNG physical fragment generation pipeline confirms that the **Fragment Container Sequence** enforces **strict monotonic progression** in both spatial layout coordinates and logical break-token offsets. Violations of monotonicity result in infinite layout loops (`DCHECK` failures) or visual overlapping/clipping artifacts. 

Below is the technical breakdown of how monotonicity is maintained across fragmentainers (columns, pages, and print frames).

---

### **2. LOGICAL MONOTONICITY (THE `BreakToken` VECTOR)**
Within a fragmentation context, a node is split across multiple `NGPhysicalBoxFragment` instances. Monotonicity is primarily governed by the `NGBlockBreakToken` pipeline.

*   **Consumed Block-Size ($B_{consumed}$):** 
    Every fragmentainer generated for a continuous flow must result in a non-decreasing consumed block-size. 
    $$\text{For fragment sequence } F_1, F_2, \dots, F_n: \quad B_{consumed}(F_{i}) \le B_{consumed}(F_{i+1})$$
*   **Strict Advancement Requirement:** 
    To prevent infinite pagination/column-generation loops, the engine enforces *strict* monotonicity ($<$) over a macro-sequence. While $B_{consumed}(F_{i}) == B_{consumed}(F_{i+1})$ is transiently permitted for zero-height fragments or pushed floats/orthogonal flows, the `SequenceNumber` of the child break tokens must strictly advance. 
*   **Starvation & Forcing:** 
    If a fragmentainer $F_i$ is too small to fit the minimum unbreakable content, Blink forces at least *one* piece of content into $F_i$ (violating block-size constraints intentionally) to guarantee that $B_{consumed}$ strictly increases for $F_{i+1}$, preserving sequence termination.

---

### **3. SPATIAL MONOTONICITY (FRAGMENTAINER GEOMETRY)**
At the container level (`NGColumnLayoutAlgorithm` / `NGPageLayoutAlgorithm`), the physical placement of the fragmentainers themselves follows a deterministic monotonic sequence based on the `WritingMode`.

*   **Inline Progression (Multi-Column):**
    In standard horizontal-tb `multicol` containers, the inline offset ($X$) of sequential column fragments is strictly increasing (LTR) or strictly decreasing (RTL) within a single row:
    $$\text{Offset}_{inline}(C_i) < \text{Offset}_{inline}(C_{i+1}) \quad \text{[LTR]}$$
    $$\text{Where } \text{Offset}_{inline}(C_{i+1}) = \text{Offset}_{inline}(C_i) + \text{ColumnWidth} + \text{ColumnGap}$$
*   **Block Progression (Column Spanners & Pagination):**
    When a `column-span: all` element interrupts the sequence, or when columns overflow into a new fragmented block row, spatial monotonicity shifts to the block axis ($Y$). The block offset of the new row strictly exceeds the block-end of the preceding fragmentainer group.

---

### **4. TREE-ORDER & INDEXING MONOTONICITY**
The `LayoutBox::PhysicalFragments()` list maintains an array of fragments associated with a single DOM node.

*   **Index Mapping:** Fragment index $0 \dots k$ maps strictly to chronological generation order.
*   **Pre-Order Traversal:** Inside a fragmentainer, child fragments are appended in a mostly monotonic pre-order DOM traversal. 
    *   *Audit Exception Note:* Out-of-Flow (OOF) positioned descendants (e.g., `position: absolute`) may temporarily bypass the standard fragment sequence until their containing block resolves, at which point they are injected into the target fragmentainer. However, once placed, their own internal fragmentation follows the strict monotonic rules above.

---

### **5. DETECTED ANOMALIES / EDGE CASES IN BLINK**
As Agent 367, I flag the following known edge cases where sequence monotonicity is stressed in the Blink codebase:

1.  **Negative Margins:** Large negative block-start margins can cause the *visual* block-offset of content in $F_{i+1}$ to appear retrograde, even though the *logical* `ConsumedBlockSize` remains monotonically increasing. Blink clamps or shifts these during break-token calculation to prevent infinite cloning.
2.  **Monolithic Content:** Elements with `break-inside: avoid` or scrollbars (`overflow: auto`) cannot be fragmented. They slice the consumed-size calculation as a single step-function rather than a continuous curve, occasionally forcing an empty fragmentainer $F_i$ (0px consumed) followed by a massive jump in $F_{i+1}$.
3.  **Clone-Decoration (`box-decoration-break: clone`):** Cloned borders and padding artificially inflate the physical size of fragments without advancing the logical content offset. Blink separates *physical* fragment size from *logical* consumed block-size to keep the sequence monotonic.

---
**STATUS:** Audit Complete. Monotonicity invariants are holding. 
**AWAITING FURTHER DIRECTIVES.**