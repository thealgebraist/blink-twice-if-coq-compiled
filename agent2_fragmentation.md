### 1. Core Data Structures in Blink LayoutNG Fragmentation

In Blink’s LayoutNG architecture, fragmentation is modeled as a resumable, immutable functional pipeline. Layout algorithms take a `LayoutInputNode`, an `ConstraintSpace`, and an optional incoming `BreakToken`, and produce a `LayoutResult` containing an immutable `PhysicalFragment` that holds an outgoing `BreakToken` if layout did not complete.

```
[LayoutInputNode] + [ConstraintSpace] + [Incoming BlockBreakToken ( Nullable )]
                                  |
                                  v
                       ( BlockLayoutAlgorithm )
                                  |
                                  v
            [PhysicalBoxFragment] ---> [Outgoing BlockBreakToken]
                      |                          |
                      +--> Child Fragments       +--> Child BreakTokens
```

#### `BreakToken` (`third_party/blink/renderer/core/layout/break_token.h`)
The base class representing a continuation point for a layout node.
*   `InputNode node_`: The `LayoutInputNode` (Block or Inline) that was interrupted.
*   `const unsigned type_ : 1`: Discriminator between `kBlockBreakToken` and `kInlineBreakToken`.
*   `const unsigned flags_`: Bitfield storing subtype-specific flags (e.g., `kIsBreakBefore`, `kIsForcedBreak`, `kIsRepeated`, `kHasSeenAllChildren`).

#### `BlockBreakToken` (`third_party/blink/renderer/core/layout/block_break_token.h`)
Encapsulates the exact resumable state of a broken box across fragmentainer boundaries.
*   `LayoutUnit consumed_block_size_`: Total block-size of the box consumed in all *previous* fragmentainers, **excluding** overflow from descendants, but **including** cloned borders/paddings if `box-decoration-break: clone` is active.
*   `LayoutUnit consumed_block_size_legacy_adjustment_`: Deprecated/transitional adjustment for monolitic/legacy frames.
*   `unsigned sequence_number_`: A monotonically increasing zero-based index tracking which fragment of the same `LayoutInputNode` is currently being generated ($0, 1, \dots, n$). Used to match states across recalculations.
*   `const BlockBreakTokenData* data_`: Optional payload for specialized layout modes (`GridBreakTokenData`, `FlexBreakTokenData`, `TableBreakTokenData`, `MulticolBreakTokenData`).
*   `Member<const BreakToken> child_break_tokens_[]`: Flexible array member storing pointers to unhandled or partially handled child `BreakToken`s.
*   **Bitflags**:
    *   `is_break_before_`: True if the node broke *before* its first piece of content (even before its border-before). Consumed block size is `0`, and no content has been placed yet.
    *   `is_forced_break_`: True if this break was caused by an explicit `break-before` or `break-after` property.
    *   `has_seen_all_children_`: True if the algorithm has iterated through all DOM/layout children of this box. The node may still break if it has remaining block-size (e.g., fixed `height` or `min-height`) or trailing border/padding that could not fit.
    *   `is_at_block_end_`: True if all content and specified `block-size` of the box have been consumed, and only trailing border/padding or overflow remains to be painted/fragmented.
    *   `is_caused_by_column_spanner_`: True if the break was forced due to encountering a `column-span: all` descendant.

#### `ConstraintSpace` (`third_party/blink/renderer/core/layout/constraint_space.h`)
Carries the top-down geometric constraints from the parent down to the current node, including fragmentation state via `ConstraintSpaceRareData`:
*   `FragmentationType block_fragmentation_type_`: Enum (`kFragmentNone`, `kFragmentColumn`, `kFragmentPage`).
*   `LayoutUnit fragmentainer_block_size_`: The total block-size capacity of the enclosing fragmentainer ($H_{\text{frag}}$).
*   `LayoutUnit fragmentainer_offset_`: The distance from the block-start edge of the enclosing fragmentainer to the block-start border-edge of the current node ($\Delta_{\text{offset}}$).
*   `bool is_at_fragmentainer_start_`: True if the node starts at the exact top of the fragmentainer (or is the first content after a break). Crucial for preventing infinite loops (guarantees progress) and collapsing margins at breaks (`MarginStrut::discard_margins`).
*   `bool min_break_appeal_`: The minimum `BreakAppeal` required for an unforced break inside this subtree to be considered valid.

#### `PhysicalBoxFragment` (`third_party/blink/renderer/core/layout/physical_box_fragment.h`)
The immutable output of a block layout pass.
*   Holds a reference to its outgoing `BlockBreakToken` (`break_token_`). If `break_token_ == nullptr`, the node has completely finished layout.
*   Contains `PhysicalFragmentLink` array representing placed children. If a child broke inside, that child's `PhysicalBoxFragment` will hold its own outgoing `BlockBreakToken`, which is simultaneously referenced in the parent's `child_break_tokens_[]` array.

#### Fragmentainer (`OutOfFlowLayoutPart` / `ColumnLayoutAlgorithm` / `PageLayoutAlgorithm`)
A fragmentainer itself is represented as a `PhysicalBoxFragment` whose `BoxType` is `kColumnBox` or `kPageArea`. It does not map to a DOM node (`node_ == nullptr` or points to the multicol container/LayoutView). Its outgoing `BlockBreakToken` chains directly to the next column or page in the fragmentation context.

---

### 2. Fragmentainer Sizing, Consumed Block Size, and Remaining Space

In Blink, fragmentation calculations use fixed-point arithmetic (`LayoutUnit`, 1/64th of a pixel). The core metric governing breaks is the fragmentainer's remaining block space, managed in `fragmentation_utils.cc`.

Let:
*   $H_{\text{frag}}$ = `space.FragmentainerBlockSize()` (total height of the column/page).
*   $\Delta_{\text{offset}}$ = `space.FragmentainerOffset()` (current node's block-start offset relative to the current fragmentainer's block-start).
*   $B_{\text{prev}}$ = `PreviousConsumedBlockSize(break_token)` (total block-size consumed by the current node in all prior fragmentainers).
*   $B_{\text{curr}}$ = Block-size of the content accumulated in the *current* fragmentainer pass for this node.
*   $B_{\text{total}}$ = Total cumulative consumed block-size after the current pass.

#### Remaining Block Space Calculation
```cpp
// FragmentainerSpaceLeft() in fragmentation_utils.h
LayoutUnit FragmentainerSpaceLeft(const ConstraintSpace& space) {
  if (!space.HasKnownFragmentainerBlockSize())
    return LayoutUnit::Max(); // Infinite space during initial column balancing pass
  LayoutUnit available_space = space.FragmentainerBlockSize() - space.FragmentainerOffset();
  return available_space.ClampNegativeToZero();
}
```
Mathematically:
$$S_{\text{left}} = \max(0, H_{\text{frag}} - \Delta_{\text{offset}})$$

*(Note: When a child node is laid out at an offset $y_{\text{child}}$ relative to its parent, its `ConstraintSpace` receives $\Delta_{\text{offset}}^{\text{child}} = \Delta_{\text{offset}}^{\text{parent}} + y_{\text{child}}$).*

#### Consumed Block Size Accumulation
When a node spans multiple fragmentainers, its intrinsic or specified CSS `block-size` ($H_{\text{css}}$) is evaluated against its total accumulated size across all fragments.
1.  **Entry State**: At the start of `BlockLayoutAlgorithm::Layout()`, if an incoming `break_token` exists (and `!break_token->IsBreakBefore()`), the algorithm initializes:
    $$B_{\text{prev}} = \text{break\_token}\rightarrow\text{ConsumedBlockSize()}$$
    The algorithm sets its internal cursor (` intrinsic_block_size_`) to `0` for the current fragmentainer, or conceptually starts at $B_{\text{prev}}$ and subtracts $B_{\text{prev}}$ at the end to compute the current fragment's height.
2.  **Box Sizing with Fragmentation**: When computing the final border-box block-size at the end of child layout (in `FinishFragmentation()`):
    Let $B_{\text{intrinsic}}$ be the block size required by children in the *current* fragmentainer. The total unconstrained block size would be:
    $$B_{\text{unconstrained}} = B_{\text{prev}} + B_{\text{intrinsic}}$$
    Blink applies CSS `height`, `min-height`, and `max-height` constraints to $B_{\text{unconstrained}}$ to find the desired total block size $H_{\text{desired}}$. The block size remaining to be allocated for this box in the current and future fragmentainers is:
    $$B_{\text{needed}} = \max(B_{\text{intrinsic}}, H_{\text{desired}} - B_{\text{prev}})$$
3.  **Clamping to the Fragmentainer**: If $B_{\text{needed}} > S_{\text{left}}$, the node cannot finish in the current fragmentainer (unless it is monolithic). The current fragment's block-size $B_{\text{curr}}$ is clamped:
    $$B_{\text{curr}} = \min(B_{\text{needed}}, S_{\text{left}})$$
    And the outgoing `BlockBreakToken` is constructed with:
    $$B_{\text{total}} = B_{\text{prev}} + B_{\text{curr}}$$

---

### 3. Forced Breaks vs. Unforced Breaks

Blink categorizes every potential break location (Class A, B, or C break points per CSS Fragmentation Level 3 §4) and evaluates them using two mechanisms: **EBreakBetween** (for forced/avoided breaks between sibling blocks) and **BreakAppeal** (for unforced breaks).

#### Break Appeal (`break_appeal.h`)
An ordered enumeration representing how desirable an unforced break is:
$$\text{kBreakAppealImpossible} < \text{kBreakAppealLastResort} < \text{kBreakAppeal ViolatingBreakAvoid} < \text{kBreakAppeal ViolatingOrphansAndWidows} < \text{kBreakAppealPerfect}$$

#### Forced Breaks (`EBreakBetween`)
During child layout (`BlockLayoutAlgorithm::LayoutNewFormattingContext` / `HandleInFlow`), Blink computes the final break-between value at the boundary between Child $i-1$ and Child $i$ using `JoinFragmentainerBreakValues(break_after_prev, break_before_curr)`.
*   **Break Propagation**: Per CSS Frag 3 §3.1, a `break-before` on a first in-flow child (or `break-after` on a last in-flow child) propagates outward to the parent block container if there is no intervening border, padding, or content. Blink collects this on `LayoutResult::InitialBreakBefore()` and `FinalBreakAfter()`.
*   **Execution**: If the resolved `EBreakBetween` is a forced break matching the current context (e.g., `EBreakBetween::kColumn` in a multicol context, or `kPage`/`kLeft`/`kRight`/`kRecto`/`kVerso` in pagination):
    1.  Blink calls `BreakBeforeChild()`.
    2.   creates a `BlockBreakToken` for Child $i$ with `is_break_before = true` and `is_forced_break = true`.
    3.  Stops processing further children in the current fragmentainer (`has_seen_all_children_ = false`).
    4.  Truncates any pending `MarginStrut` (margins after a forced break are preserved at the top of the next fragmentainer; margins *before* the forced break are truncated).

#### Unforced Breaks (`BreakBeforeChildIfNeeded` in `fragmentation_utils.cc`)
When Child $i$ is laid out, Blink checks if it fits within $S_{\text{left}}$.
1.  **Inside Break**: If Child $i$ is fragmentable and broke *internally*, its `LayoutResult` will contain an outgoing `BlockBreakToken`. If the child's break appeal is acceptable ($\ge \text{min\_break\_appeal}$), the parent accepts the broken child fragment, records the child's break token, and stops laying out further siblings.
2.  **Overflowing Child**: If Child $i$ is monolithic (e.g., an image, `break-inside: avoid` that refused to break, or a line box) or its block-end exceeds $S_{\text{left}}$ ($\Delta_{\text{offset}}^{\text{child}} + H_{\text{child}} > H_{\text{frag}}$):
    *   Blink calculates the `BreakAppeal` of breaking *before* Child $i$.
    *   If the boundary between Child $i-1$ and Child $i$ has `break-after: avoid` or `break-before: avoid`, the appeal is downgraded to `kBreakAppealViolatingBreakAvoid`.
    *   **Early Break Registration**: During child layout, whenever Blink passes a valid break point with high appeal (e.g., `kBreakAppealPerfect` between Child $k-1$ and Child $k$) that fits within the fragmentainer, it records an `EarlyBreak` structure on the algorithm state.
    *   **Relayout with EarlyBreak**: If Child $i$ overflows the fragmentainer, and breaking *before* Child $i$ has lower appeal (e.g., violates `break-before: avoid` or `widows`/`orphans`) than the previously recorded `EarlyBreak` at Child $k$, Blink **aborts** the current layout pass and re-runs `BlockLayoutAlgorithm` with the `EarlyBreak` injected into the `ConstraintSpace`, forcing an unforced break at Child $k$.

---

### 4. Margin Truncation at Break Boundaries

W3C CSS Fragmentation Level 3 §5.2 dictates that adjoining margins at an unforced break must be truncated (collapsed to zero), while margins after a forced break must be preserved.

Blink implements this via `MarginStrut` (`third_party/blink/renderer/core/layout/margin_strut.h`).

```cpp
struct MarginStrut {
  LayoutUnit positive_margin;
  LayoutUnit negative_margin;
  bool discard_margins = false;

  void Append(LayoutUnit value, bool is_quirky) {
    if (discard_margins)
      return;
    // Standard positive/negative margin accumulation
  }
  LayoutUnit Sum() const {
    if (discard_margins)
      return LayoutUnit();
    return positive_margin + negative_margin;
  }
};
```

#### Rules of `discard_margins` in Blink:
1.  **At Fragmentainer Start (After an Unforced Break)**:
    When a block begins or resumes at the top of a fragmentainer (`space.IsAtFragmentainerStart()` is true):
    *   If the incoming `BlockBreakToken` is **not** marked `IsForcedBreak()` (and it's not the very first fragment of the root formatting context / multicol container itself), the initial `MarginStrut` created at the top of `BlockLayoutAlgorithm::Layout()` sets:
        ```cpp
        margin_strut.discard_margins = true;
        ```
    *   As the algorithm descends into the first in-flow child (or resumes a broken child that broke