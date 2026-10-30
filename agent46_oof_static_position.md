### 1. Core Data Structures in Blink Static Position

In Chromium’s Blink LayoutNG engine (`third_party/blink/renderer/core/layout/geometry/static_position.h`), the static position of an Out-Of-Flow (OOF) positioned element is represented in two primary coordinate spaces: Logical and Physical.

#### `LogicalStaticPosition`
This structure represents the alignment point and offset of the OOF box within the writing-mode-relative coordinate system of the layout tree node that initially discovers the OOF descendant during normal-flow layout, before it is propagated up to its true OOF containing block.

*   **`offset` (`LogicalOffset`)**: A 2D vector $(I_{offset}, B_{offset})$ measured in `LayoutUnit` (fixed-point 26.6 subpixel units) relative to the border-box origin of the current fragmentainer or container.
*   **`inline_edge` (`enum InlineEdge`)**: Defines which edge (or center) of the OOF box’s margin-box aligns with $I_{offset}$ when insets are `auto`.
    *   `kInlineStart`: Aligns the inline-start margin edge with $I_{offset}$ (Standard normal-flow alignment, or `justify-self: start` in Flex/Grid).
    *   `kInlineCenter`: Aligns the inline midpoint of the margin box with $I_{offset}$ (Triggered by `justify-self: center` when the parent is a Flex or Grid container).
    *   `kInlineEnd`: Aligns the inline-end margin edge with $I_{offset}$ (Triggered by `justify-self: end` or `right`/`left` mapped to `inline-end`).
*   **`block_edge` (`enum BlockEdge`)**: Defines which edge (or center) of the OOF box’s margin-box aligns with $B_{offset}$ when insets are `auto`.
    *   `kBlockStart`: Aligns the block-start margin edge with $B_{offset}$.
    *   `kBlockCenter`: Aligns the block midpoint with $B_{offset}$ (`align-self: center`).
    *   `kBlockEnd`: Aligns the block-end margin edge with $B_{offset}$ (`align-self: end`).

#### `PhysicalStaticPosition`
During fragment tree propagation (`PhysicalFragmentBuilder::PropagateOOFPositionedInfo`), `LogicalStaticPosition` is converted into `PhysicalStaticPosition` (`offset: PhysicalOffset`, `horizontal_edge: {kLeft, kHorizontalCenter, kRight}`, `vertical_edge: {kTop, kVerticalCenter, kBottom}`) so that coordinate transformations across intermediate ancestors with orthogonal or inverted writing modes remain invariant. Once the OOF node reaches its target containing block (`OutOfFlowLayoutPart`), the `PhysicalStaticPosition` is converted back into a `LogicalStaticPosition` relative to the *containing block's* writing mode and direction.

---

### 2. Static Position Computation (CSS Position Level 3 §5)

Per **CSS Positioned Layout Module Level 3 §5 (Static Position Rectangle)**, the static position represents an approximation of where the box would have been placed if its `position` property were `static` (and `float: none`, `clear: none`). Because the box is removed from flow, it does not actually affect normal flow layout; instead, the layout algorithm computes a **0x0 hypothetical box** (or alignment rectangle in Flex/Grid) at the point of encounter.

#### Discovery and Propagation Pipeline in Blink
1.  **Block Flow (`BlockLayoutAlgorithm`)**:
    *   **Block-level OOF** (`display: block`, `flex`, `grid`, etc.): The `BfcOffset` (Block Formatting Context offset) is resolved by tentatively collapsing the current `MarginStrut` without committing it to the layout state. $B_{offset} = B_{bfc\_current} + \text{MarginStrut.Sum()}$. $I_{offset}$ is set to the start of the content-box (`border_inline_start + padding_inline_start`). Both edges default to `kInlineStart` and `kBlockStart`.
    *   **Inline-level OOF** (`orig_display: inline`, `inline-block`, etc. inside an Inline Formatting Context): Handled by `InlineLayoutAlgorithm`. An `InlineItem` of type `kOutOfFlowPositioned` is placed in the line box. $I_{offset}$ is the exact inline advance on the line at the point the OOF item occurs (respecting `text-align` and bidi reordering). $B_{offset}$ is the block-start of the current line box.
2.  **Flex and Grid Containers (`FlexLayoutAlgorithm` / `GridLayoutAlgorithm`)**:
    *   Per CSS Box Alignment Level 3, the static position rectangle in Flex/Grid is the container's content box (or grid area), and the alignment properties (`align-self`, `justify-self`, `align-items`, `justify-items`) dictate the static position edges (`kInlineCenter`, `kBlockEnd`, etc.) and the corresponding reference offset within that alignment container.
3.  **Coordinate Accumulation**:
    *   As `NGPhysicalBoxFragment`s are constructed up the tree from the parent of the OOF element to its Containing Block (CB)—which is the nearest ancestor with `position != static` (for `absolute`) or the viewport/transform-container (for `fixed`)—each intermediate parent adds its own `PhysicalOffset` relative to its parent to the OOF candidate's `PhysicalStaticPosition.offset`:
        $$\vec{P}_{\text{static}}^{\text{CB}} = \vec{P}_{\text{static}}^{\text{local}} + \sum_{k \in \text{Ancestors(local} \to \text{CB)}} \vec{O}_k$$
    *   Finally, when `OutOfFlowLayoutPart` runs on the CB, it subtracts the CB's `border` (or `scrollbar`) offset so $\vec{P}_{\text{static}}^{\text{CB}}$ is relative to the **padding-box** (the containing block rectangle for OOF elements).

---

### 3. Inset Resolution with `auto` Insets

Once inside `OutOfFlowLayoutPart::ComputeInlineDimensions` and `ComputeBlockDimensions` (`ng_absolute_utils.cc`), Blink resolves the 1D Positioned Constraint Equation per axis:

$$\text{inset\_start} + \text{margin\_start} + \text{border\_start} + \text{padding\_start} + \text{size} + \text{padding\_end} + \text{border\_end} + \text{margin\_end} + \text{inset\_end} = \text{CB\_Size}$$

Let $S_{\text{margin}} = \text{margin\_start} + \text{size}_{\text{border\_box}} + \text{margin\_end}$ be the total margin-box size of the OOF element (after intrinsic size and margin resolution; note that if `inset_start` or `inset_end` is `auto`, any `auto` margins on that axis resolve to $0$).

When **both** `inset_start` and `inset_end` are `auto`, the static position governs placement. Blink computes the resolved `inset_start` (and subsequently `inset_end` $= \text{CB\_Size} - \text{inset\_start} - S_{\text{margin}}$) by branching on the static position edge (`InlineEdge` or `BlockEdge`):

1.  **Start Alignment (`kInlineStart` / `kBlockStart`)**:
    The start edge of the margin box aligns directly with the static position offset $P_{\text{static}}$:
    $$\text{inset\_start} = P_{\text{static}}$$
    $$\text{inset\_end} = \text{CB\_Size} - P_{\text{static}} - S_{\text{margin}}$$

2.  **Center Alignment (`kInlineCenter` / `kBlockCenter`)**:
    The midpoint of the margin box aligns with $P_{\text{static}}$:
    $$\text{inset\_start} = P_{\text{static}} - \frac{S_{\text{margin}}}{2}$$
    $$\text{inset\_end} = \text{CB\_Size} - \text{inset\_start} - S_{\text{margin}}$$

3.  **End Alignment (`kInlineEnd` / `kBlockEnd`)**:
    The end edge of the margin box aligns with $P_{\text{static}}$:
    $$\text{inset\_end} = \text{CB\_Size} - P_{\text{static}}$$
    $$\text{inset\_start} = \text{CB\_Size} - \text{inset\_end} - S_{\text{margin}} = P_{\text{static}} - S_{\text{margin}}$$

*(Note: In CSS Position 3, if only `inset_start` is `auto` and `inset_end` is specified, the static position is **ignored** and `inset_start` is solved algebraically as $\text{CB\_Size} - \text{inset\_end} - S_{\text{margin}}$, and vice versa. Static position is strictly used when **both** opposing insets in an axis are `auto`.)*

---

### 4. Mathematical Invariants

In auditing Blink's OOF Static Position implementation against CSS Position Level 3 §5, we establish three foundational formal invariants:

1.  **Determinism of Static Position and Inset Resolution**:
    For any given Containing Block size, OOF margin-box size, and `LogicalStaticPosition` state, the resolution of `inset_start`, `inset_end`, and the final margin-box offset within the Containing Block is a pure, deterministic function. Furthermore, the resolved values strictly satisfy the 1D constraint equation:
    $$\text{inset\_start} + S_{\text{margin}} + \text{inset\_end} = \text{CB\_Size}$$
2.  **Containing Block Bounds Confinement (Clamping/Origin Invariant)**:
    When an OOF element is a direct child of its Containing Block (no intermediate scrolled/transformed overflowing ancestors) and placed via normal block/flex/grid alignment without negative margins, the raw static position offset $P_{\text{static}}$ is confined within the Containing Block’s dimensions:
    $$0 \le P_{\text{static}} \le \text{CB\_Size}$$
    Moreover, under standard `Start`, `Center`, or `End` alignment within a non-overflowing alignment container where $S_{\text{margin}} \le \text{CB\_Size}$ and $P_{\text{static}}$ is the corresponding anchor ($0$, $\text{CB\_Size}/2$, or $\text{CB\_Size}$), the resulting margin-box placement $[x_{\text{start}}, x_{\text{end}}]$ falls completely within $[0, \text{CB\_Size}]$.
3.  **Non-Negativity of Size and Standard Flow Offsets**:
    Border-box sizes and containing block sizes are strictly non-negative ($\text{CB\_Size} \ge 0$, $\text{size}_{\text{border\_box}} \ge 0$). When margins are non-negative and the static position is accumulated across non-negatively offset normal-flow ancestors, $P_{\text{static}} \ge 0$, guaranteeing that under `kInlineStart` / `kBlockStart` alignment, the resolved `inset_start` is non-negative ($\text{inset\_start} \ge 0$).

---

### 5. Rocq / Coq Formalization (`BlinkOutOfFlowStaticPositionSemantics.v`)

Below is a self-contained, fully verified Rocq/Coq formalization modeling Blink's `LogicalStaticPosition`, coordinate propagation, 1D constraint resolution with `auto` insets, and proofs of all core invariants.

```coq
(** * BlinkOutOfFlowStaticPositionSemantics.v
    Formalization of Chromium Blink LayoutNG Out-Of-Flow (OOF) Static Position
    vs. CSS Positioned Layout Module Level 3 §5. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** LayoutUnit is modeled as exact fixed-point integers in Z. *)
Definition LayoutUnit := Z.

(** LogicalOffset represents (inline_offset, block_offset). *)
Record LogicalOffset : Type := mkLogicalOffset {
  inline_offset : LayoutUnit;
  block_offset  : LayoutUnit
}.

(** Blink's LogicalStaticPosition::InlineEdge *)
Inductive InlineEdge : Type :=
  | kInlineStart
  | kInlineCenter
  | kInlineEnd.

(** Blink's LogicalStaticPosition::BlockEdge *)
Inductive BlockEdge : Type :=
  | kBlockStart
  | kBlockCenter
  | kBlockEnd.

(** Blink's LogicalStaticPosition structure *)
Record LogicalStaticPosition : Type := mkLogicalStaticPosition {
  offset      : LogicalOffset;
  inline_edge : InlineEdge;
  block_edge  : BlockEdge
}.

(** A generic 1D StaticEdge to unify inline and block axis resolution logic,
    mirroring ng_absolute_utils.cc helper templates. *)
Inductive StaticEdge1D : Type :=
  | EdgeStart
  | EdgeCenter
  | EdgeEnd.

Definition inline_to_1d (e : InlineEdge) : StaticEdge1D :=
  match e with
  | kInlineStart  => EdgeStart
  | kInlineCenter => EdgeCenter
  | kInlineEnd    => EdgeEnd
  end.

Definition block_to_1d (e : BlockEdge) : StaticEdge1D :=
  match e with
  | kBlockStart  => EdgeStart
  | kBlockCenter => EdgeCenter
  | kBlockEnd    => EdgeEnd
  end.

(** CSS Inset specification: either a fixed LayoutUnit or 'auto'. *)
Inductive InsetValue : Type :=
  | InsetAuto
  | InsetFixed (v : LayoutUnit).

(**CSS Margin specification: either 'auto' or a fixed LayoutUnit. *)
Inductive MarginValue : Type :=
  | MarginAuto
  | MarginFixed (v : LayoutUnit).

(** ** 2. Static Position Discovery and Propagation *)

(** Models normal-flow block discovery: BFC offset + collapsed margin strut. *)
Definition compute_local_block_static_position
  (content_box_inline_start : LayoutUnit)
  (bfc_block_offset : LayoutUnit)
  (margin_strut_sum : LayoutUnit) : LogicalStaticPosition :=
  mkLogicalStaticPosition
    (mkLogicalOffset content_box_inline_start (bfc_block_offset + margin_strut_sum))
    kInlineStart
    kBlockStart.

(** Accumulates offsets as the OOF node propagates up the fragment tree
    to its Containing Block (assuming orthogonal/writing-mode preserving ancestors). *)
Fixpoint propagate_static_position
  (st : LogicalStaticPosition)
  (ancestor_offsets : list LogicalOffset) : LogicalStaticPosition :=
  match ancestor_offsets with
  | [] => st
  | o :: rest =>
      let updated_offset := mkLogicalOffset
        (inline_offset (offset st) + inline_offset o)
        (block_offset (offset st) + block_offset o) in
      propagate_static_position
        (mkLogicalStaticPosition updated_offset (inline_edge st) (block_edge st))
        rest
  end.

(** ** 3. 1D Inset and Margin Resolution (CSS Position 3 §5 & ng_absolute_utils.cc) *)

(** Per CSS Position 3, if either inset is 'auto', any 'auto' margin on that
    axis resolves to