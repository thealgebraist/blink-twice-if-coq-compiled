# Agent 49 Audit Report: Chromium Blink Paint Layer Stacking Order vs. CSS 2.1 Appendix E

**Target Subsystem:** `third_party/blink/renderer/core/paint/`  
**Primary Specification:** CSS 2.1 Appendix E ("Elaborate description of Stacking Contexts"), updated by CSS Positioned Layout Module Level 3, CSS Transforms Module Level 1, and CSS Will-Change Module Level 1.

---

## 1. Core Data Structures in Blink Paint Layering

In Chromium's Blink rendering engine, the translation from the DOM/LayoutObject tree to the CSS 2.1 Appendix E painting order is mediated by an auxiliary tree of `PaintLayer` objects and their associated stacking metadata. Note that not every `LayoutObject` creates a `PaintLayer`; normal-flow block, float, and inline descendants without self-painting layer requirements are painted directly by their enclosing `PaintLayer` via `BoxPainter` and `BlockPainter`.

### 1.1 `PaintLayer` (`paint_layer.h`)
A `PaintLayer` is allocated for `LayoutBoxModelObject` instances that require independent geometry, clipping, scrolling, or stacking isolation (e.g., root elements, positioned elements, transparent elements, transforms, overflow clip/scroll).

* **Tree Pointers:** `parent_`, `first_child_`, `last_child_`, `next_`, `previous_`. These pointers strictly maintain the DOM/Layout tree preorder topology among layer-owning layout objects.
* **Classification Flags:**
  * `is_self_painting_layer_`: True if the layer paints its own content rather than delegating to its `LayoutObject` container's normal-flow painting phase.
  * `has_SelfPaintingLayerDescendant_`: Dirty-bit tracked up the ancestor chain to optimize traversal skips.
* **Stacking Context Identification:** `GetLayoutObject().StyleRef().IsStackingContext()` determines if this layer acts as an atomic stacking root (isolating its descendants' z-ordering from ancestors).

### 1.2 `PaintLayerStackingNode` (and Consolidated Stacking Lists in `PaintLayer`)
Historically encapsulated as `PaintLayerStackingNode` and subsequently inlined/consolidated onto `PaintLayer` (via rare data / bitfields to minimize memory footprint), this conceptual node manages the z-order lists for a stacking context or a normal-flow paint container.

* **`pos_z_order_list_` (`HeapVector<Member<PaintLayer>>*`):** Contains descendant `PaintLayer`s that belong to this stacking context and have `z-index >= 0` (or `z-index: auto` when establishing a stacking context or positioned layer). Sorted stably in ascending order of `EffectiveZIndex()`.
* **`neg_z_order_list_` (`HeapVector<Member<PaintLayer>>*`):** Contains descendant `PaintLayer`s belonging to this stacking context with `z-index < 0`. Sorted stably in ascending order of `EffectiveZIndex()` (e.g., `-5` precedes `-1`).
* **`normal_flow_list_` (`HeapVector<Member<PaintLayer>>*`):** Contains immediate or descendant `PaintLayer`s that do not participate in z-ordering (e.g., unpositioned layers with `overflow: hidden` or self-painting layers for hardware-accelerated scrolling that do not form stacking contexts).
* **Dirty Bit Management:** `dirty_z_order_lists_` and `dirty_normal_flow_list_`. When layout or style mutates (`StyleDidChange`), `DirtyStackingContextZOrderLists()` invalidates these vectors. Rebuilding is lazily triggered via `UpdateDescendantDependentFlags()` and `RebuildZOrderLists()` before the `PrePaint` or `Paint` lifecycle phases.

### 1.3 `PaintLayerPaintOrderIterator` (`paint_layer_paint_order_iterator.h`)
An iterator abstraction that abstracts away the physical `first_child_`/`next_` tree pointers and instead yields child `PaintLayer`s in the exact sequence mandated by Appendix E.

```cpp
enum PaintLayerIteration {
  kNegativeZOrderChildren = 1 << 0,
  kNormalFlowChildren     = 1 << 1,
  kPositiveZOrderChildren = 1 << 2,
  kAllChildren            = kNegativeZOrderChildren | kNormalFlowChildren | kPositiveZOrderChildren
};
```
When initialized with a root `PaintLayer` and a bitmask of `PaintLayerIteration`, `PaintLayerPaintOrderIterator::Next()` lazily calls `UpdateZOrderLists()` and `UpdateNormalFlowList()` on the root layer, then iterates sequentially through `neg_z_order_list_`, `normal_flow_list_`, and `pos_z_order_list_`.

### 1.4 `PaintPhase` (`paint_phase.h`) and `PaintLayerPaintingInfo`
While `PaintLayerPaintOrderIterator` orders *layers*, `PaintPhase` orders the *sub-components* painted within a single `PaintLayer` (i.e., the non-layer `LayoutObject` tree underneath that `PaintLayer`).

```cpp
enum class PaintPhase {
  kBlockBackground = 0,          // Phase 1 (Stacking context background) & Phase 3 (Child block backgrounds)
  kSelfBlockBackgroundOnly = 1,  // Phase 1 isolated
  kDescendantBlockBackgroundsOnly = 2, // Phase 3 isolated
  kFloat = 3,                    // Phase 4 (Non-positioned floats)
  kForeground = 4,               // Phase 5 (Normal-flow inline content, text, replaced elements)
  kOutline = 5,                  // Outlines (CSS 2.1 E.2 Step 7/8)
  kSelfOutlineOnly = 6,
  kDescendantOutlinesOnly = 7,
  kOverlayOverflowControls = 8,  // Scrollbars
  kSelectionDragImage = 9,
  kTextClip = 10,
  kMask = 11,
  kClippingMask = 12,
};
```

---

## 2. The 7-Phase Stacking Context Painting Order

In Blink, the orchestration of the 7 phases of CSS 2.1 Appendix E is split across two levels of recursion: `PaintLayerPainter::PaintLayerContents` (which coordinates `PaintLayer` hierarchies) and `LayoutObject::Paint` (which coordinates non-layer layout trees using `PaintPhase`).

| Appendix E Phase | CSS 2.1 Specification | Blink Execution Mechanism (`PaintLayerPainter` & `BoxPainter`) |
| :--- | :--- | :--- |
| **Phase 1** | Background and borders of the element forming the stacking context. | `PaintLayerPainter` invokes `PaintFragmentWithPhase(PaintPhase::kSelfBlockBackgroundOnly)`. Paints the box decorations (background color/image, border, box-shadow) of the root `PaintLayer`'s `LayoutObject`. |
| **Phase 2** | Stacking contexts formed by positioned/transformed descendants with negative `z-index` (most negative first). | `PaintLayerPaintOrderIterator` configured with `kNegativeZOrderChildren`. Iterates over `neg_z_order_list_`. For each child `PaintLayer`, recursively calls `PaintLayerPainter::Paint()`. |
| **Phase 3** | Non-positioned, in-flow, block-level descendants (backgrounds and borders only). | `PaintLayerPainter` invokes `PaintFragmentWithPhase(PaintPhase::kDescendantBlockBackgroundsOnly)` on the current layer, **interleaved** with `kNormalFlowChildren` from `normal_flow_list_` (for self-painting non-stacking layers). |
| **Phase 4** | Non-positioned floating descendants. | `PaintLayerPainter` invokes `PaintFragmentWithPhase(PaintPhase::kFloat)`. `BlockPainter` traverses the floating objects list (`FloatingObjects`) of descendant blocks, painting each float as an atomic pseudo-stacking context (phases 1, 3, 4, 5, 6 of the float). |
| **Phase 5** | Normal-flow, inline-level, non-positioned descendants (including inline-block, inline-table, and block-level replaced elements, plus text content of all in-flow blocks). | `PaintLayerPainter` invokes `PaintFragmentWithPhase(PaintPhase::kForeground)`. Traverses NGPaintFragment / FragmentItems (InlineCursor) to paint text, inline boxes, and atomic inlines (`inline-block` paints as a pseudo-stacking context). Also invokes `PaintPhase::kDescendantOutlinesOnly` and `kSelfOutlineOnly`. |
| **Phase 6** | Positioned descendants (and pseudo-stacking contexts like `opacity < 1`, `transform`, flex/grid items with `z-index != auto`) with `z-index: auto` or `z-index: 0`. | Handled by the first segment of `kPositiveZOrderChildren` in `pos_z_order_list_` where `EffectiveZIndex() == 0`. If `z-index: auto` does *not* form a full stacking context (i.e., `position: relative` with `z-index: auto`), its own positioned descendants are hoisted into *this* parent stacking context's lists, while the layer itself paints its local phases 1, 3, 4, 5 here in Phase 6. |
| **Phase 7** | Stacking contexts formed by positioned descendants with positive `z-index` (`z-index >= 1`), in ascending order. | Handled by the remainder of `kPositiveZOrderChildren` in `pos_z_order_list_` where `EffectiveZIndex() > 0`. Recursively invokes `PaintLayerPainter::Paint()` for each layer. |

### Crucial Architectural Edge Case: Interleaving in Phases 3, 4, and 5
When an in-flow non-positioned descendant has a `PaintLayer` (e.g., a `div` with `overflow: scroll` or `will-change: scroll-position` that does *not* create a stacking context in legacy modes, or a self-painting layer for compositing), it resides in `normal_flow_list_`. Blink paints the root layer's `kDescendantBlockBackgroundsOnly`, `kFloat`, and `kForeground`, and then iterates `normal_flow_list_`. Because normal-flow layers are non-positioned, their relative overlap with non-layer siblings is strictly determined by DOM tree order and flow layout geometry.

---

## 3. Stable Sorting of Z-Indices and Tree Order Preservation

### 3.1 Tree Collection (`CollectLayers`)
During `PaintLayer::RebuildZOrderLists()`, Blink performs a **preorder depth-first traversal** of the `PaintLayer` tree starting at the stacking context root:

```cpp
void PaintLayer::CollectLayers(
    HeapVector<Member<PaintLayer>>*& neg_z_order_list,
    HeapVector<Member<PaintLayer>>*& pos_z_order_list) {
  for (PaintLayer* child = FirstChild(); child; child = child->NextSibling()) {
    // 1. If the child belongs to this stacking context's z-order lists, append it.
    if (!child->IsNormalFlowOnly()) {
      int z_index = child->GetLayoutObject().StyleRef().EffectiveZIndex();
      // Note: EffectiveZIndex() is 0 for both 'z-index: 0' and 'z-index: auto'
      if (z_index < 0) {
        EnsureList(neg_z_order_list)->push_back(child);
      } else {
        EnsureList(pos_z_order_list)->push_back(child);
      }
    }
    // 2. If the child does NOT establish its own stacking context,
    // recursively hoist its descendants into the current stacking context's lists!
    if (!child->GetLayoutObject().StyleRef().IsStackingContext()) {
      child->CollectLayers(neg_z_order_list, pos_z_order_list);
    }
  }
}
```

### 3.2 Stable Sorting (`std::stable_sort`)
Immediately after `CollectLayers` populates `neg_z_order_list_` and `pos_z_order_list_` in strict **DOM preorder**, Blink sorts both vectors using `std::stable_sort`:

```cpp
static bool LayerZOrderCompare(const Member<PaintLayer>& first,
                               const Member<PaintLayer>& second) {
  return first->GetLayoutObject().StyleRef().EffectiveZIndex() <
         second->GetLayoutObject().StyleRef().EffectiveZIndex();
}

if (neg_z_order_list_) {
  std::stable_sort(neg_z_order_list_->begin(), neg_z_order_list_->end(),
                   LayerZOrderCompare);
}
if (pos_z_order_list_) {
  std::stable_sort(pos_z_order_list_->begin(), pos_z_order_list_->end(),
                   LayerZOrderCompare);
}
```

**Why `std::stable_sort` is Mandatory:**  
CSS 2.1 Appendix E.2 states that when two elements share the same `z-index` (including when one has `z-index: 0` and another has `z-index: auto`), they must be painted in document tree order (preorder). Because `CollectLayers` visits nodes in exact preorder traversal before sorting, `std::stable_sort` guarantees that for any two layers $L_1, L_2$ with $\text{EffectiveZIndex}(L_1) = \text{EffectiveZIndex}(L_2)$, their relative index in the sorted vector preserves their relative insertion order from `CollectLayers`, which is precisely $\text{tree\_order}(L_1) < \text{tree\_order}(L_2)$.

---

## 4. Mathematical Invariants

Let $\mathcal{N}$ be the finite set of paintable items within the scope of a single stacking context root $R$ (i.e., $R$ itself and all descendants of $R$ up to, and including the roots of, any nested child stacking contexts, without descending *into* nested stacking contexts).

Each node $x \in \mathcal{N}$ is equipped with:
1. $\text{id}(x) \in \mathbb{N}$: The preorder traversal index in the DOM/Layout tree, establishing a **strict total order** $<_{\text{tree}}$ on $\mathcal{N}$ where $x <_{\text{tree}} y \iff \text{id}(x) < \text{id}(y)$. Since preorder indices are unique, $\text{id}$ is injective: $\text{id}(x) = \text{id}(y) \iff x = y$.
2. $\phi(x) \in \{1, 2, 3, 4, 5, 6, 7\}$: The Appendix E phase assignment function.
3. $z(x) \in \mathbb{Z}$: The effective z-index. By CSS semantics:
   * $\phi(x) = 2 \implies z(x) < 0$
   * $\phi(x) = 6 \implies z(x) = 0$ (representing both `z-index: auto` and `z-index: 0`)
   * $\phi(x) = 7 \implies z(x) > 0$
   * $\phi(x) \in \{1, 3, 4, 5\} \implies z(x) = 0$ (unused for inter-phase comparisons).

### 4.1 Definition of the Stacking Order Relation ($<_{\text{paint}}$)
For any $x, y \in \mathcal{N}$, $x$ is painted before (underneath) $y