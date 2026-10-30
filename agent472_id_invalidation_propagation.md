**AUDIT LOG: SUBSYSTEM BLINK_ID_INVALIDATION**
**AUDITOR:** Agent 472
**SUBJECT:** Descendant Propagation Mechanics (Layout, Paint, and Compositing)

---

### 1. Executive Summary
In the Blink rendering engine, direct ID or node-level invalidation rarely remains isolated. To avoid costly full-tree recalculations, Blink utilizes a series of dirty-bit flags and hierarchical traversal mechanisms to propagate invalidation states to descendants. 

Audit findings categorize descendant propagation into four primary phases: **DOM/Style**, **Layout**, **PrePaint (Property Trees)**, and **Paint/Compositing**.

---

### 2. Phase I: DOM & Style Invalidation (`InvalidateStyle`)
When an element's ID, class, or attribute is mutated, Blink avoids immediately dirtying the entire subtree. Instead, it relies on **Invalidation Sets**.

*   **Mechanism:** `StyleEngine` schedules `InvalidationSet` objects on the mutated element. 
*   **Descendant Propagation (`StyleInvalidator`):** During the next lifecycle update, `StyleInvalidator` walks the DOM tree. It carries a `PendingInvalidations` state downward.
*   **Targeting:** Rather than marking all descendants `kLocalStyleChange`, the invalidator checks if the descendant matches the specific ID/Class selectors held in the active `DescendantInvalidationSet`.
*   **Fallback (`kSubtreeStyleChange`):** If a mutation is too broad (e.g., structural DOM changes or universal selectors), the node is marked with `kSubtreeStyleChange`, forcing a full style recalculation on all descendants unconditionally.

### 3. Phase II: Layout Propagation (`LayoutObject`)
Once styles are recalculated, `LayoutObject` diffs the `ComputedStyle`. If geometry is affected, layout invalidation propagates downward.

*   **Upward Marking, Downward Execution:** Marking a node for layout (`SetNeedsLayout`) walks *up* the ancestor chain setting `ChildNeedsLayout` bits. However, the actual invalidation of cached geometry happens *downward* during the `UpdateLayout` phase.
*   **LayoutNG Constraint Spaces:** In LayoutNG, descendant propagation is handled via `NGConstraintSpace`. If a parent’s layout is invalidated and its size changes, it generates a new `NGConstraintSpace` for its children. 
*   **Cache Busting:** Descendant `NGLayoutResult` caches are invalidated only if the incoming `NGConstraintSpace` differs from the cached space, or if `NeedsLayout()` is explicitly set on the descendant.

### 4. Phase III: PrePaint & Property Tree Propagation (`PrePaintTreeWalk`)
*Critical Audit Area:* This is the primary mechanism where IDs (specifically `CompositorElementId` and `UniqueId`) are synchronized and invalidated across descendants.

The `PrePaintTreeWalk` executes a depth-first traversal of the `LayoutObject` tree to update the four Property Trees (Transform, Clip, Effect, Scroll) and issue paint invalidations.

*   **Context Passing:** The walk maintains a `PrePaintTreeWalkContext` struct. As it descends, it copies parent states (e.g., `paint_invalidation_container`, `tree_builder_context`) to the child context.
*   **Subtree Flags:** If an ancestor is marked with `kSubtreeInvalidation` (via `PaintInvalidationReason`), the `PrePaintTreeWalkContext` sets a forced invalidation flag. All subsequent descendants visited in that branch will have their `LayoutObject::MutableForPainting` state dirtied.
*   **Property Node Invalidation:** If an ancestor's CSS transform or opacity changes, its corresponding `TransformPaintPropertyNode` or `EffectPaintPropertyNode` is marked dirty. Because descendant property nodes hold pointers to their parent nodes, a change in an ancestor node implicitly invalidates the world-space matrix or accumulated effect of all descendants without needing to rewrite the descendants' individual property nodes.
*   **CompositorElementId:** If an element's ID changes or is removed, its `CompositorElementId` (used for CC animations and scrolling) is updated here, and descendant layers referencing this ID as a scroll/clip parent are updated via the `PaintArtifactCompositor`.

### 5. Phase IV: Paint & Raster Invalidation (`PaintController`)
At the leaf level of the invalidation cascade, Blink must tell the compositor (`cc`) which display items are dead.

*   **DisplayItemClient IDs:** Every `LayoutObject` is a `DisplayItemClient`. Its memory address (combined with fragment data) acts as its ID in the `PaintController`.
*   **Subsequence Caching:** Blink groups descendants into subsequences (typically per `PaintLayer`). If an ancestor `PaintLayer` is marked `SetNeedsRepaint`, it invalidates the entire subsequence, forcing all descendant `DisplayItemClient`s to regenerate their `DisplayItem`s.
*   **Chunk-to-Layer Mapping:** During `PaintArtifactCompositor::Update`, invalidated `PaintChunk`s (which carry the `PropertyTreeState` and IDs from PrePaint) are mapped to `cc::Layer`s. Descendant chunks that share a backing layer with an invalidated parent chunk may trigger raster invalidation via `RasterInvalidator` if their visual rects intersect or shift.

---

### 6. Vulnerability / Bottleneck Assessment (Agent 472 Notes)
1.  **Subtree Walk Over-Invalidation:** Forced `kSubtreeStyleChange` or `SetSubtreeShouldDoFullPaintInvalidation` bypasses all Blink caching mechanisms. Ensure ID mutations are strictly scoped to `DescendantInvalidationSet` to prevent $O(N)$ tree walks.
2.  **Fragmentation (LayoutNG):** When an element fragments (e.g., multi-column), a single `LayoutObject` generates multiple `NGPhysicalFragment`s, each requiring a unique `FragmentData` ID. Invalidation propagation must iterate through the `FragmentData` linked list for *every* descendant, multiplying traversal costs.

**END OF REPORT.**