### 1. Core Data Structures in Blink Flex Direction

In Chromium’s Blink rendering engine (LayoutNG), CSS Flexible Box Layout Level 1 §5 (Ordering and Orientation) is implemented through the `FlexLayoutAlgorithm` pipeline. The architecture separates logical flow resolution from physical coordinate mapping by maintaining direction-agnostic line construction and applying post-resolution coordinate mirroring for reverse axes.

```
+-------------------------------------------------------------------------+
|                           FlexLayoutAlgorithm                           |
|  +-------------------+   +-------------------+   +-------------------+  |
|  |   ConstructAnd    |   |  GiveItemsFinal   |   |  MirrorMainAxis   |  |
|  |  AppendFlexItems  |-->|     Position      |-->|  & WrapReverse    |  |
|  +-------------------+   +-------------------+   +-------------------+  |
+-------------------------------------------------------------------------+
             |                                               |
             v                                               v
+-------------------------+                     +-------------------------+
|       FlexItem          |                     |     NGFlexLine          |
| - main_axis_final_size  |                     | - line_items_           |
| - offset (LogicalOffset)|                     | - cross_axis_offset_    |
| - margins               |                     | - cross_axis_extent_    |
+-------------------------+                     +-------------------------+
```

#### `FlexLayoutAlgorithm` (`third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.h`)
The central state machine orchestrating flex layout. It inherits from `LayoutAlgorithm` and manages the lifecycle of `FlexLine` instances. Key methods governing reverse directions include:
* `ConstructAndAppendFlexItems()`: Queries `ComputedStyle` to determine `is_column_`, `is_wrap_reverse_`, and `is_horizontal_flow_`.
* `GiveItemsFinalPositionAndSize()`: Iterates over `FlexLine` outputs, computing main-axis and cross-axis offsets in a normalized forward-flow space before conditionally applying axis inversion transformations.

#### `FlexDirection` & `FlexWrap` (`third_party/blink/renderer/core/style/computed_style_constants.h`)
Blink encodes CSS `flex-direction` and `flex-wrap` properties as strongly typed enums:
```cpp
enum class EFlexDirection : uint8_t {
  kRow,
  kRowReverse,
  kColumn,
  kColumnReverse
};

enum class EFlexWrap : uint8_t {
  kNowrap,
  kWrap,
  kWrapReverse
};
```
Within `FlexLayoutAlgorithm` and `FlexibleBoxAlgorithm`, these are evaluated alongside the writing mode (`WritingDirectionMode`) to compute boolean state flags:
* `Style().ResolvedIsRowReverseFlexDirection()` / `Style().ResolvedIsColumnReverseFlexDirection()`
* `Style().FlexWrap() == EFlexWrap::kWrapReverse`

#### `FlexItem` & `NGFlexItem` (`third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.h`)
Represents a single child box participating in flex layout (historically `FlexItem`, transitioned to `NGFlexItem` in LayoutNG). It stores layout-resolved geometry in **flex-logical coordinates** (main and cross axes) rather than physical screen coordinates (`x`, `y`) or writing-mode logical coordinates (`inline`, `block`):
* `LayoutUnit flex_base_content_size_`: The initial main size before flexing.
* `LayoutUnit main_axis_final_size_`: The resolved outer or border-box main size after `ResolveFlexibleLengths()`.
* `NGBoxStrut physical_margins_` / `FlexColumnRowMargins`: Margins mapped to main-start, main-end, cross-start, and cross-end.
* `LogicalOffset offset_`: A mutable reference or output structure holding the item’s resolved `(main_axis_offset, cross_axis_offset)` relative to the flex container's content box.

---

### 2. Coordinate Mirroring Transformations

Per CSS Flexible Box Layout Level 1 §5.1 (`flex-direction`) and §5.2 (`flex-wrap`), reverse directions invert the `main-start`/`main-end` or `cross-start`/`cross-end` axes. Blink implements this by executing the line-breaking and space-distribution algorithms (`justify-content`, `align-content`, `align-items`) in a canonical forward direction $[0, \text{container\_size}]$, and subsequently applying an affine reflection over the container's inner dimension.

#### Main-Axis Mirroring (`row-reverse` and `column-reverse`)
During `GiveItemsFinalPositionAndSize()`, items are initially placed sequentially along the main axis starting from `main_axis_start_offset` (which includes container border/padding start). If the main axis is reversed (`EFlexDirection::kRowReverse` or `EFlexDirection::kColumnReverse`), Blink transforms the main-axis offset of each item within the container's content box.

Let:
* $C_{\text{main}}$ be the `container_main_size` (the inner content-box main size of the flex container).
* $I_{\text{offset}}$ be the `item_main_offset` (the item's border-box offset relative to the container's main-start content edge).
* $I_{\text{size}}$ be the `item_main_size` (the item's border-box main size).

The reflection transformation $\mathcal{M}_{\text{main}}$ is defined as:

$$\mathcal{M}_{\text{main}}(C_{\text{main}}, I_{\text{offset}}, I_{\text{size}}) = C_{\text{main}} - (I_{\text{offset}} + I_{\text{size}})$$

*Note on Blink's internal border-box adjustment:* In `FlexLayoutAlgorithm`, offsets often include `border_scrollbar_padding` during intermediate passes. If $I_{\text{raw\_offset}}$ includes `main_axis_start_padding` ($P_{\text{start}}$) and $W_{\text{total}}$ is the total container border-box main size ($W_{\text{total}} = P_{\text{start}} + C_{\text{main}} + P_{\text{end}}$), Blink computes:
$$\text{offset}_{\text{mirrored}} = W_{\text{total}} - P_{\text{end}} - I_{\text{raw\_offset}} - I_{\text{size}} + P_{\text{start}}$$
Substituting $I_{\text{offset}} = I_{\text{raw\_offset}} - P_{\text{start}}$ and $C_{\text{main}} = W_{\text{total}} - P_{\text{start}} - P_{\text{end}}$ reduces this identically to the canonical content-box formula:
$$\text{offset}_{\text{content\_mirrored}} = C_{\text{main}} - (I_{\text{offset}} + I_{\text{size}})$$

#### Cross-Axis Mirroring (`wrap-reverse`)
When `flex-wrap: wrap-reverse` is active, the cross-start and cross-end directions are swapped (§5.2). Flex lines (`NGFlexLine`) are constructed and stacked sequentially from `cross_axis_offset = 0`. Once `AlignFlexLines()` finishes distributing free cross-axis space, Blink inverts the cross-axis positioning of every line.

Let:
* $C_{\text{cross}}$ be the `container_cross_size` (the inner content-box cross size of the flex container).
* $L_{\text{offset}}$ be the `line_cross_offset` (the cross-axis offset of the `NGFlexLine` relative to the content box).
* $L_{\text{size}}$ be the `line_cross_size` (the `cross_axis_extent_` of the flex line).

The line reflection transformation $\mathcal{M}_{\text{cross}}$ is defined as:

$$\mathcal{M}_{\text{cross}}(C_{\text{cross}}, L_{\text{offset}}, L_{\text{size}}) = C_{\text{cross}} - (L_{\text{offset}} + L_{\text{size}})$$

Additionally, for individual items within a `wrap-reverse` line, `align-self: flex-start` and `flex-end` resolve against the flipped `cross-start` and `cross-end`. Within the line's local cross space $[0, L_{\text{size}}]$, an item aligned to `cross-start` in `wrap-reverse` is placed at the bottom/right of the line:
$$I_{\text{local\_cross\_offset}} = L_{\text{size}} - I_{\text{cross\_size}} - I_{\text{margin\_cross\_end}}$$

---

### 3. Mathematical Invariants

To verify the soundness of Blink's coordinate transformations against CSS Flexible Box Level 1 §5, we establish three foundational invariants over $\mathbb{Z}$ (modeling Blink's fixed-point `LayoutUnit` arithmetic).

#### Invariant 1: Coordinate Involution (Mirroring Twice Yields Identity)
The mirroring transformation $\mathcal{M}(C, x, s) = C - (x + s)$ is an involution with respect to the offset $x$. Applying the transformation twice restores the exact original coordinate:

$$\mathcal{M}(C, \mathcal{M}(C, x, s), s) = C - ((C - (x + s)) + s) = C - (C - x) = x$$

*Significance:* This guarantees that axis reversal is lossless and symmetric. Reversing a reversed layout (e.g., mapping `row-reverse` combined with `direction: rtl` back to physical coordinates) cannot introduce rounding drift or off-by-one pixel shifts in `LayoutUnit`.

#### Invariant 2: Strict Bounds Containment
If a flex item (or flex line) is validly contained within the container's content box prior to mirroring, it remains strictly contained within the container's content box after mirroring.

Given the forward-layout preconditions:
1. $0 \le x$ (The item starts at or after the container's start edge).
2. $0 \le s$ (The item has a non-negative size).
3. $x + s \le C$ (The item's far edge does not exceed the container's size).

Let $x' = \mathcal{M}(C, x, s) = C - (x + s)$. Then:
1. **Lower bound ($0 \le x'$):** Since $x + s \le C$, subtracting $(x + s)$ from both sides yields $0 \le C - (x + s) = x'$.
2. **Upper bound ($x' + s \le C$):** $x' + s = C - (x + s) + s = C - x$. Since $0 \le x$, it follows that $C - x \le C$, hence $x' + s \le C$.

#### Invariant 3: Determinism and Order Reversal
For any given container configuration and item geometry, the layout transformation is a pure, deterministic function. Furthermore, for any two non-overlapping sequential items $A$ and $B$ in forward flow where $x_A + s_A \le x_B$, their mirrored counterparts satisfy $x'_B + s_B \le x'_A$, strictly inverting their topological order along the axis without introducing overlap.

---

### 4. Formal Verification in Rocq / Coq (`BlinkFlexReverseAxisSemantics.v`)

The following file provides a complete, self-contained formalization of the data structures, coordinate mirroring semantics, and proofs of all invariants in Rocq/Coq (compatible with Coq 8.16+ / Rocq 9.0+).

```coq
(** * BlinkFlexReverseAxisSemantics.v
    Formal verification of Chromium Blink's CSS Flexible Box Level 1 §5
    reverse-axis coordinate transformations (row-reverse, column-reverse, wrap-reverse). *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** CSS `flex-direction` property (CSS Flexbox §5.1) *)
Inductive FlexDirection : Type :=
  | Row
  | RowReverse
  | Column
  | ColumnReverse.

(** CSS `flex-wrap` property (CSS Flexbox §5.2) *)
Inductive FlexWrap : Type :=
  | Nowrap
  | Wrap
  | WrapReverse.

(** Container geometry in flex-logical coordinates (modeling Blink's LayoutUnit as Z) *)
Record FlexContainer : Type := mkFlexContainer {
  direction : FlexDirection;
  wrap : FlexWrap;
  container_main_size : Z;
  container_cross_size : Z
}.

(** Logical representation of a single FlexItem within a line *)
Record LogicalFlexItem : Type := mkLogicalFlexItem {
  item_id : nat;
  item_main_offset : Z;
  item_main_size : Z;
  item_cross_offset : Z;
  item_cross_size : Z
}.

(** Logical representation of an NGFlexLine *)
Record FlexLine : Type := mkFlexLine {
  line_cross_offset : Z;
  line_cross_size : Z;
  line_items : list LogicalFlexItem
}.

(** ** 2. Axis Reversal Predicates and Mirroring Transformations *)

(** Determines if the main axis is reversed *)
Definition is_main_reverse (dir : FlexDirection) : bool :=
  match dir with
  | RowReverse | ColumnReverse => true
  | Row | Column => false
  end.

(** Determines if the cross axis is reversed *)
Definition is_cross_reverse (w : FlexWrap) : bool :=
  match w with
  | WrapReverse => true
  | Nowrap | Wrap => false
  end.

(** Core 1D coordinate reflection:
    offset' = container_size - (offset + size) *)
Definition mirror_coord (container_size offset size : Z) : Z :=
  container_size - (offset + size).

(** Transform a single item's main-axis offset *)
Definition transform_item_main (c_main : Z) (rev_main : bool) (item : LogicalFlexItem) : LogicalFlexItem :=
  let new_main_offset :=
    if rev_main then mirror_coord c_main (item_main_offset item) (item_main_size item)
    else item_main_offset item
  in
  mkLogicalFlexItem
    (item_id item)
    new_main_offset
    (item_main_size item)
    (item_cross_offset item)
    (item_cross_size item).

(** Transform a single item's cross-axis offset given its parent line's cross offset *)
Definition transform_item_cross (c_cross : Z) (rev_cross : bool) (item : LogicalFlexItem) : LogicalFlexItem :=
  let new_cross_offset :=
    if rev_cross then mirror_coord c_cross (item_cross_offset item) (item_cross_size item)
    else item_cross_offset item
  in
  mkLogicalFlexItem
    (item_id item)
    (item_main_offset item)
    (item_main_size item)
    new_cross_offset
    (item_cross_size item).

(** Transform a FlexLine and all of its constituent items (Blink's GiveItemsFinalPositionAndSize) *)
Definition transform_flex_line (container : FlexContainer) (line : FlexLine) : FlexLine :=
  let rev_main := is_main_reverse (direction container) in
  let rev_cross := is_cross_