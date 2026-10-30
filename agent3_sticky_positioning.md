### 1. Core Data Structures in Blink Sticky Positioning

In Chromium's Blink rendering engine (post-LayoutNG / Fragment-based architecture), sticky positioning is decoupled from the core static layout pass so that scroll updates can be computed on the compositor thread (`cc::TransformNode`) or quickly updated during lifecycle paint/compositing steps without triggering full layout invalidations.

#### `StickyPositionScrollingConstraints` (`third_party/blink/renderer/core/layout/ sticky_position_scrolling_constraints.h`)
This struct holds the precomputed geometry required to resolve a sticky element’s offset at any given scroll position. All rects are stored in the **scroll container's scrollable overflow coordinate space** (excluding current scroll offset, i.e., relative to the scroll origin).

```cpp
struct StickyPositionScrollingConstraints {
  // Specified insets from CSS (top, bottom, left, right).
  // std::optional<LayoutUnit> in modern Blink, or flags + LayoutUnit.
  std::optional<LayoutUnit> top_inset;
  std::optional<LayoutUnit> bottom_inset;
  std::optional<LayoutUnit> left_inset;
  std::optional<LayoutUnit> right_inset;

  // The containing block's content box (modified by sticky padding/margins)
  // within the scroll container's content-box coordinate space.
  PhysicalRect scroll_container_relative_containing_block_rect;

  // The sticky element's border box (or margin box, when computing against CB)
  // at its static (unshifted) position, relative to the scroll container.
  PhysicalRect scroll_container_relative_sticky_box_rect;

  // For nested sticky elements: the nearest sticky ancestor affecting the
  // sticky box rect, and the nearest sticky ancestor affecting the containing block rect.
  LayoutObject* nearest_sticky_layer_shifting_sticky_box = nullptr;
  LayoutObject* nearest_sticky_layer_shifting_containing_block = nullptr;

  // Cached total sticky offset applied in the most recent composition pass.
  PhysicalOffset total_sticky_box_sticky_offset;
  PhysicalOffset total_containing_block_sticky_offset;
};
```

#### `StickyConstraintsMap`
Defined on the `PaintLayerScrollableArea` (or propagated via `PhysicalFragment` RareData onto the scroll container's `PaintLayer`):
```cpp
using StickyConstraintsMap = HeapHashMap<Member<const PaintLayer>, StickyPositionScrollingConstraints>;
```
Because the map iterates in topological (DOM / pre-order tree) sequence during offset updates, ancestor sticky elements are guaranteed to have their `total_sticky_box_sticky_offset` computed *before* descendant sticky elements query them.

#### `PhysicalRect` and `ScrollContainerRelative` Coordinate Space
* **`PhysicalRect`**: A tuple $(x, y, width, height) \in \mathbb{Q}^4$ (implemented via `LayoutUnit`, a 26.6 fixed-point integer representing $1/64\text{th}$ of a CSS pixel).
* **`ScrollContainerRelative` Space**: Let the scroll container's border box be at the origin, adjusted by `border_left` and `border_top` to define the **scrollport origin** at scroll offset $(0, 0)$. Any point $P$ inside the scrolling content is measured relative to the unscrolled layout flow origin of that scroller. When the user scrolls by $\mathbf{s} = (s_x, s_y)$, the visible **scrollport rect** $V(\mathbf{s})$ in `ScrollContainerRelative` space is:
  $$V(\mathbf{s}) = [s_x, s_x + W_v] \times [s_y, s_y + H_v]$$
  where $W_v, H_v$ are the scrollport width and height (`clientWidth`, `clientHeight`, minus scrollbars).

---

### 2. 1D Sticky Constraint Equation

Since horizontal ($X$) and vertical ($Y$) sticky axes are orthogonal in CSS Position 3, we formalize the 1D vertical ($Y$) axis. The horizontal axis is identical under the substitution $(y, H, \text{top}, \text{bottom}) \mapsto (x, W, \text{left}, \text{right})$ (modulo inline-base directionality for over-constrained insets).

#### Variables (in `ScrollContainerRelative` coordinates)
* $s \in \mathbb{R}$: Current scroll offset along the axis ($s \ge 0$ in standard LTR/TTB).
* $V_0 = s, \quad V_1 = s + L_v$: The start and end edges of the scrollport of length $L_v \ge 0$.
* $B_0, B_1$: The static (unshifted) start and end edges of the **sticky box** ($B_1 = B_0 + L_b$, where $L_b \ge 0$ is the sticky box margin-box size).
* $C_0, C_1$: The start and end edges of the **containing block content box** ($C_1 = C_0 + L_c$, where $L_c \ge 0$).
* $i_0, i_1 \in \mathbb{R} \cup \{\bot\}$: The specified `top` ($i_0$) and `bottom` ($i_1$) sticky insets.

#### Step 1: Viewport Sticky View Rectangle ($S_0, S_1$)
The sticky view rectangle is the scrollport inset by $i_0$ and $i_1$:
$$S_0 = V_0 + \text{unwrap}(i_0, 0) = s + i_0, \qquad S_1 = V_1 - \text{unwrap}(i_1, 0) = s + L_v - i_1$$

#### Step 2: Unclamped Sticky Desire ($\delta_{\text{desire}}$)
In CSS Position 3 and Blink (`ComputeStickyOffset`), start and end insets apply asymmetrically, with the **start inset ($i_0$) winning** if both are triggered or if the sticky view rectangle is smaller than the sticky box:

1. **Bottom/End Push ($\delta_{\text{end}}$)**: If $i_1 \neq \bot$ and the sticky box's static bottom edge $B_1$ exceeds $S_1$, it is pulled up (negative offset):
   $$\delta_{\text{end}} = \begin{cases} \min(0, S_1 - B_1) = \min(0, s + L_v - i_1 - B_1) & \text{if } i_1 \neq \bot \\ 0 & \text{otherwise} \end{cases}$$

2. **Top/Start Push ($\delta_{\text{start}}$)**: If $i_0 \neq \bot$ and the (potentially end-shifted) sticky box's top edge falls above $S_0$, it is pushed down (positive offset):
   $$\delta_{\text{start}} = \begin{cases} \max(0, S_0 - (B_0 + \delta_{\text{end}})) = \max(0, s + i_0 - B_0 - \delta_{\text{end}}) & \text{if } i_0 \neq \bot \\ 0 & \text{otherwise} \end{cases}$$

The combined unclamped sticky offset is $\delta_{\text{raw}} = \delta_{\text{end}} + \delta_{\text{start}}$.

#### Step 3: Containing Block ClampingBounds ($\Delta_{\min}, \Delta_{\max}$)
Per CSS Position 3 § 3.4, a sticky element **must not move outside its static position directionally against its inset**, nor **escape its containing block rectangle** $[C_0, C_1]$. However, if the sticky box is already larger than or outside its containing block statically, clamping must not invert the interval.

* **Maximum downward shift ($\Delta_{\max}$)**: The sticky box's bottom edge $B_1 + \delta$ cannot exceed $C_1$, and downward movement caused by `top` inset cannot be negative:
  $$\Delta_{\max} = \max(0, C_1 - B_1)$$
* **Minimum upward shift ($\Delta_{\min}$)**: The sticky box's top edge $B_0 + \delta$ cannot go above $C_0$, and upward movement caused by `bottom` inset cannot be positive:
  $$\Delta_{\min} = \min(0, C_0 - B_0)$$

#### Step 4: The Unified Clamping Equation
Combining the push directions with the containing block bounds yields the canonical 1D sticky offset equation:
$$\delta_{\text{sticky}}(s) = \text{clamp}\Big(\Delta_{\min}, \; \delta_{\text{raw}}(s), \; \Delta_{\max}\Big)$$
where $\text{clamp}(\text{lo}, x, \text{hi}) = \max(\text{lo}, \min(x, \text{hi}))$.

If only a `top` inset $i_0$ is specified ($i_1 = \bot$), this simplifies directly to the classic single-inset formula:
$$\delta_{\text{sticky}}(s) = \text{clamp}\big(0, \; s + i_0 - B_0, \; \max(0, C_1 - B_1)\big)$$

---

### 3. Composition Across Multiple Sticky Ancestors and Nested Scrolling Contexts

#### Case A: Multiple Sticky Ancestors in the *Same* Scroll Container
Suppose sticky element $k$ is a DOM descendant of sticky ancestors within the same scroll container. Blink tracks two ancestor pointers in `StickyPositionScrollingConstraints`:
1. $A_{\text{box}}(k)$: `nearest_sticky_layer_shifting_sticky_box` — the closest sticky ancestor between $k$ and the scroll container in the layout tree.
2. $A_{\text{cb}}(k)$: `nearest_sticky_layer_shifting_containing_block` — the closest sticky ancestor between $k$'s containing block and the scroll container.

Let $\Delta_{\text{total}}^{\text{box}}(a)$ be the accumulated sticky offset of ancestor $a$. Before computing $k$'s own local sticky offset $\delta_k(s)$, $k$'s static sticky box and containing block rects must be shifted into their **live positions** induced by ancestor sticky shifts:

$$\tilde{B}_0(k) = B_0(k) + \Delta_{\text{total}}^{\text{box}}\big(A_{\text{box}}(k)\big)$$
$$\tilde{C}_0(k) = C_0(k) + \Delta_{\text{total}}^{\text{box}}\big(A_{\text{cb}}(k)\big)$$

Then $k$'s local sticky offset $\delta_k(s)$ is computed using $\tilde{B}(k)$ and $\tilde{C}(k)$ against the scrollport $[s, s + L_v]$:
$$\delta_k(s) = \mathcal{F}_{\text{sticky}}\big(s, L_v, i_0, i_1, \tilde{B}_0(k), L_b(k), \tilde{C}_0(k), L_c(k)\big)$$
And $k$'s total sticky box shift relative to the unshifted scroll container content becomes:
$$\Delta_{\text{total}}^{\text{box}}(k) = \Delta_{\text{total}}^{\text{box}}\big(A_{\text{box}}(k)\big) + \delta_k(s)$$

*Physical Paint Offset*: Because Blink's fragment/paint tree is hierarchical, painting $k$ inside $A_{\text{box}}(k)$ already inherits $\Delta_{\text{total}}^{\text{box}}(A_{\text{box}}(k))$ from the parent's transform node. Thus, the **local paint/compositor transform** applied to $k$'s own node is solely $\delta_k(s)$.

#### Case B: Nested Scrolling Contexts (Inner Scroller inside Outer Scroller)
According to W3C CSS Position 3 § 3.4, a sticky element only sticks to its **nearest ancestor scroll container** (the nearest ancestor with `overflow` other than `visible`).
* Let $S_{\text{outer}}$ have scroll offset $s_{\text{outer}}$ and $S_{\text{inner}}$ have scroll offset $s_{\text{inner}}$.
* Sticky elements inside $S_{\text{inner}}$ evaluate their constraints strictly as a function of $s_{\text{inner}}$ within $S_{\text{inner}}$'s `ScrollContainerRelative` space.
* In world (root frame) coordinates, the final screen position of a sticky element $k \in S_{\text{inner}}$ (where $S_{\text{inner}}$ itself might be inside a sticky element $m \in S_{\text{outer}}$) is a linear transformation composition:
  $$P_{\text{screen}}(k) = P_{\text{static}}(S_{\text{outer}}) - s_{\text{outer}} + \Delta_{\text{total}}^{\text{box}}(m, s_{\text{outer}}) + P_{\text{static}}(S_{\text{inner}}) - s_{\text{inner}} + P_{\text{static}}(k) + \Delta_{\text{total}}^{\text{box}}(k, s_{\text{inner}})$$
Crucially, $s_{\text{outer}}$ **never** leaks into the constraint equation of $k \in S_{\text{inner}}$ unless `overflow: clip` or `visible` is used on $S_{\text{inner}}$ (in which case $S_{\text{inner}}$ is not a scroll container).

---

### 4. Mathematical Invariants, Edge Cases, and Blink vs. W3C Divergences

#### Core Mathematical Invariants
1. **Static-Bound Containment Invariant**:
   For any scroll offset $s$, the shifted sticky box $[\tilde{B}_0 + \delta_k, \tilde{B}_1 + \delta_k]$ satisfies:
   $$\min(\tilde{B}_0, \tilde{C}_0) \le \tilde{B}_0 + \delta_k \quad \land \quad \tilde{B}_1 + \delta_k \le \max(\tilde{B}_1, \tilde{C}_1)$$
   When the sticky box is statically contained within its containing block ($\tilde{C}_0 \le \tilde{B}_0$ and $\tilde{B}_1 \le \tilde{C}_1$):
   $$\tilde{C}_0 \le \tilde{B}_0 + \delta_k \le \tilde{B}_1 + \delta_k \le \tilde{C}_1$$
2. **Clamping Idempotence**:
   Re-applying the containing block clamping operator $\mathcal{C}_{[\Delta_{\min}, \Delta_{\max}]}$ to an already clamped sticky offset produces no change:
   $$\mathcal{C}_{[\Delta_{\min}, \Delta_{\max}]}(\delta_k(s)) = \delta_k(s)$$
3. **Monotonicity with respect to Scroll Offset $s$**:
   For fixed geometry and insets, the sticky offset function $s \mapsto \delta_k(s)$ is **monotonically non-decreasing** (weakly increasing) and Lipschitz continuous with Lipschitz constant $L = 1$:
   $$\forall s_1 \le s_2, \quad 0 \le \delta_k(s_2) - \delta_k(s_1) \le s_2 - s_1$$
   *(Consequently, the screen position $B_0 + \delta_k(s) - s$ is monotonically non-increasing in $s$: scrolling down never causes a sticky box to move downward on the physical screen).*

