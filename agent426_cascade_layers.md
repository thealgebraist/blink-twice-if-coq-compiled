**AUDIT REPORT: Blink CSS Engine (`CascadeLayerMap` & `ElementRuleCollector`)**
**AUDITOR:** Agent 426
**SUBJECT:** `@layer` Cascade Ordering & Monotonic Resolution Mechanics

### 1. Executive Summary
In Blink’s CSS engine (located within `third_party/blink/renderer/core/css/`), CSS Cascade Layers (`@layer`) are resolved by mapping a hierarchical tree of layer declarations into a flat, monotonically increasing unsigned 16-bit integer space (`uint16_t`). This resolution ensures that rule comparison during the cascade phase operates in $O(1)$ time complexity with respect to layer precedence.

---

### 2. Core Data Structures

1. **`StyleRuleBase::LayerName`**: A vector of `AtomicString` representing a potentially nested layer name (e.g., `["framework", "theme"]`).
2. **`RuleSet::CascadeLayer`**: Forms a tree structure representing the declared layer hierarchy within a single stylesheet. Implicitly declared outer layers and anonymous layers are allocated distinct nodes.
3. **`CascadeLayerMap`**: The global (TreeScope-level) aggregator that merges `RuleSet::CascadeLayer` trees from all active stylesheets and computes the final monotonic indices.

---

### 3. The Monotonic Resolution Pipeline

The transformation from stylesheet syntax to monotonic integers occurs in three distinct phases during style recalculation:

#### Phase A: Local Tree Construction (`RuleSet`)
As the CSS parser encounters `@layer` statement rules (`@layer a, b;`) or block rules (`@layer a { ... }`), `RuleSet` constructs a local n-ary tree of `CascadeLayer` objects. 
* **Pre-order Allocation:** Sibling layers are appended to the parent node's `direct_sub_layers_` vector in the exact lexical order of their *first* appearance.
* **Anonymous Layers:** Each un-named `@layer` block generates a unique `CascadeLayer` node with an empty name, preventing subsequent layers from merging into it.
* **Implicit Outer Layer:** Rules declared outside any `@layer` block are assigned to a default, implicit root layer pointer (`nullptr` or a designated root sentinel).

#### Phase B: Tree Merging (`CascadeLayerMap`)
When a `TreeScope` (Document or ShadowRoot) updates its active stylesheets, `CascadeLayerMap` iterates through all active `RuleSet` instances in stylesheet order:
1. It constructs a canonical, merged `CascadeLayer` tree.
2. As it traverses each `RuleSet`’s local layer tree, it attempts to match named layers to existing nodes in the canonical tree.
3. If a named layer already exists at the current hierarchy level, its sub-layers are merged into the existing node. If not, a new node is appended to the canonical parent's children list.

#### Phase C: Depth-First Post-Order Monotonic Assignment
Once the canonical tree is fully merged, `CascadeLayerMap` assigns the final monotonic order values via a **Depth-First Post-Order Traversal**:

```cpp
// Conceptual representation of Blink's layer order assignment
uint16_t next_order = 0;

void ComputeLayerOrder(CanonicalCascadeLayer* layer) {
  for (CanonicalCascadeLayer* sub_layer : layer->GetDirectSubLayers()) {
    ComputeLayerOrder(sub_layer);
  }
  layer->SetOrder(++next_order);
}
```

**Why Post-Order?**
According to the CSS Cascading and Inheritance Level 5 specification, sub-layers have *lower* priority than rules declared directly within their parent layer (for normal rules). Post-order traversal visits all children before the parent, guaranteeing the invariant:
$$\text{Order}(\text{Parent}.\text{Child}_1) < \text{Order}(\text{Parent}.\text{Child}_2) < \dots < \text{Order}(\text{Parent})$$

**Unlayered Rules:**
The implicit outer layer (representing unlayered styles) is the root of the canonical tree. Because the traversal is post-order, the root is visited **last**. It receives the highest monotonic value (`CascadeLayerMap::kImplicitOuterLayerOrder`, defined as `std::numeric_limits<uint16_t>::max()`, or `65535`).

---

### 4. Cascade Priority Inversion (`!important`)

Monotonic layer order values are designed to align directly with **normal** (non-important) rule precedence: a higher integer wins. However, CSS specs dictate that for `!important` rules, earlier-declared layers override later-declared layers (and layered `!important` rules override unlayered `!important` rules).

Blink handles this without mutating the monotonic values by inverting the layer integer during cascade priority encoding in `CascadePriority`:

```cpp
// Simplified logic from third_party/blink/renderer/core/css/cascade_priority.h
uint16_t GetLayerOrder(uint16_t monotonic_order, bool is_important) {
  if (is_important) {
    return ~monotonic_order; // Bitwise NOT inverts the monotonic scale
  }
  return monotonic_order;
}
```

By applying a bitwise NOT (`~`) to the 16-bit `layer_order` when the `is_important` flag is set:
* `kImplicitOuterLayerOrder` (`0xFFFF`) becomes `0x0000` (lowest priority among important rules).
* The very first declared layer (`0x0001`) becomes `0xFFFE` (highest priority among important rules).

This preserves strict monotonicity across the entire cascade priority bitfield, allowing `StyleCascade` to compare two rules using a single 64-bit integer comparison (`CascadePriority::operator<`).

---

### 5. Audit Findings & Edge Cases

* **16-Bit Overflow Saturation:** The monotonic counter uses `uint16_t`. If a document defines $\ge 65,534$ distinct cascade layers, the counter saturates at `0xFFFE` (reserving `0xFFFF` for the implicit outer layer). Layers beyond this threshold collapse into the same precedence bucket and fall back to source order.
* **Shadow DOM Encapsulation:** Layer order is strictly scoped to a `TreeScope`. `CascadeLayerMap` instances do not bleed across Shadow DOM boundaries. Shadow host vs. slotted content precedence is resolved at the `CascadeOrigin` / TreeOrder level, higher in the `CascadePriority` bitfield than the `layer_order` bits.

**STATUS:** Resolution algorithm verified as strictly monotonic and spec-compliant. **Audit Complete.**