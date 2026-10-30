**AUDIT LOG: AGENT 396**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/css/`)
**SUBJECT:** CSS Container Query `cqi` (Container Query Inline) Unit Resolution

---

### 1. Definition & Spec Compliance
The `cqi` unit represents `1%` of the query container's **inline size**. 
In Blink, resolution of `cqi` requires traversing the flat tree to locate the nearest ancestor establishing a valid query container for inline dimensions, fetching its physical geometry, mapping that geometry to the container’s logical writing mode, and scaling the value inside `CSStoLengthConversionData`.

### 2. Core Blink Classes Involved
*   `CSSPrimitiveValue`: Holds the `kCqi` unit type.
*   `CSSToLengthConversionData`: Context object passed during style resolution (`StyleResolverState`) containing `ContainerSizes`.
*   `ContainerQueryEvaluator`: Caches and evaluates the physical/logical dimensions of the container during LayoutNG (`NGBlockNode`).
*   `LayoutBox` / `PhysicalSize`: Holds the actual layout boundaries.

### 3. Resolution Pipeline

#### Phase A: Ancestor Discovery (`ContainerSizes` Pre-computation)
When resolving style for an element utilizing `cqi`, `CSSToLengthConversionData` queries the `ContainerSizes` struct. Blink searches up the **Flat Tree** (`FlatTreeTraversal::ParentElement`) for the nearest ancestor with `ComputedStyle` matching:
1.  `container-type: inline-size` OR `container-type: size`.
2.  Specifically, the ancestor must apply **inline-size containment** (or full size containment).

*Audit Note:* If no such ancestor exists, Blink falls back to the **Small Viewport Size** (`svi` - Small Viewport Inline), which resolves against the `LayoutView` (initial containing block).

#### Phase B: Logical Axis Mapping (The Writing Mode Trap)
A critical phase in Blink's `cqi` resolution is determining *which* physical axis represents the inline size. 
*   **Rule:** The inline axis is determined by the **Query Container's** `writing-mode`, *not* the `writing-mode` of the element where the `cqi` unit is declared.

Inside Blink, this is resolved via:
```cpp
// Conceptual representation of Blink's axis resolution
WritingMode container_writing_mode = container_element->GetComputedStyle()->GetWritingMode();
bool is_horizontal = IsHorizontalWritingMode(container_writing_mode);
```
*   If `is_horizontal` is `true` (`horizontal-tb`): Inline size = Container's Physical **Width**.
*   If `is_horizontal` is `false` (`vertical-rl`, `vertical-lr`, `sideways-rl`, `sideways-lr`): Inline size = Container's Physical **Height**.

#### Phase C: Extracting Layout Geometry
Blink does not guess the size from CSS properties; it extracts the **content-box** size from the LayoutNG fragment data attached to the container's `ContainerQueryEvaluator`.

1.  During the layout pass of the container, `NGBlockNode::Layout` intercepts the geometry.
2.  `ContainerQueryEvaluator::SizeContainerUpdated` is called with the new `PhysicalSize` (content-box).
3.  The `LogicalSize` is computed by converting the `PhysicalSize` using the container's `WritingMode`.
4.  `inline_size` is extracted (`LogicalSize.inline_size`).

#### Phase D: Byte-Level Conversion (`CSSToLengthConversionData`)
When the child's style is being calculated (`StyleBuilderConverter`), the `CSSPrimitiveValue` multiplies its raw double value by the resolved basis:

```cpp
// Inside CSSToLengthConversionData::ContainerSizes
std::optional<double> ContainerSizes::InlineSize() const {
  // Traverses tree or uses cached LayoutObject size
  // Returns LayoutUnit converted to double (CSS pixels)
}

// Conversion calculation
double resolved_px = value * (container_sizes.InlineSize() / 100.0);
```

### 4. Edge Cases & Interleaved Style/Layout (Blink Specifics)

1.  **Style/Layout Interleaving:** Because `cqi` depends on layout (the size of the parent), Blink cannot resolve it during the standard top-down `RecalcStyle` pass before layout occurs. Blink pauses style recalc at the container, performs LayoutNG on the container to find its `inline_size`, updates the `ContainerQueryEvaluator`, and *then* resumes `RecalcStyle` for the subtree.
2.  **Display: None / Non-atomic Inlines:** If the container is `display: contents`, `display: none`, or a standard `display: inline` box, size containment fails to apply. Blink invalidates the container size, and `cqi` falls back to the small viewport inline size (`svi`).
3.  **Subpixel Precision:** The container's inline size is stored as a `LayoutUnit` (1/64th of a pixel precision) during LayoutNG, converted to `double` for CSS math operations (`calc(50cqi + 10px)`), and clamped back to `LayoutUnit` or `float` depending on the target CSS property (e.g., `width` vs `transform`).
4.  **Shadow DOM:** Traversal strictly uses `FlatTreeTraversal`. A `cqi` unit inside a `<slot>` resolves against the `<slot>`'s assigned shadow host or internal shadow tree container, not the light DOM parent.

**AUDIT STATUS:** COMPLETE. Pipeline verified against Blink LayoutNG / StyleEngine architecture.