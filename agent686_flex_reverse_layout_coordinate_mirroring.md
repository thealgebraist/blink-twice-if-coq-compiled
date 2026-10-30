# Formal Verification Report: Flex `row-reverse` and `column-reverse` Coordinate Mirroring in Chromium Blink

**Agent ID:** Formal Verification Agent 686 (W3C/WHATWG Layout Rules & Blink LayoutNG)  
**Target Source:** `third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc`  
**Specification:** CSS Flexible Box Layout Module Level 1 (W3C Candidate Recommendation) § 5.1 & § 9  
**Formal Theory Target:** `BlinkFlexReverseLayoutCoordinateMirroringSemantics.v`  
**Mathematical Property:** $\text{reverse\_offset}(\text{offset}, \text{item\_size}, \text{container\_size}) = \text{container\_size} - \text{offset} - \text{item\_size}$

---

## 1. Normative W3C CSS Flexbox Specification Requirements

In the CSS Flexible Box Layout Module Level 1, the `flex-direction` property specifies how flex items are placed in the flex container by setting the direction of the flex container’s main axis.

### 1.1 Main-Axis Directionality (§ 5.1)
According to **CSS Flexbox 1 § 5.1 (`flex-direction` Property)**:
* **`row`**: The flex container’s main axis has the same orientation as the inline axis of the current writing mode. The *main-start* is the equivalent of *inline-start*, and *main-end* is the equivalent of *inline-end*.
* **`row-reverse`**: Same orientation as `row`, except the *main-start* and *main-end* directions are swapped.
* **`column`**: The flex container’s main axis has the same orientation as the block axis of the current writing mode. The *main-start* is the equivalent of *block-start*, and *main-end* is the equivalent of *block-end*.
* **`column-reverse`**: Same orientation as `column`, except the *main-start* and *main-end* directions are swapped.

### 1.2 Coordinate Transformation Semantics (§ 9.5 Main-Axis Alignment)
During the Flex Layout Algorithm (§ 9), items are ordered, flexible lengths are resolved, and items are aligned along the main axis from *main-start* to *main-end*. However, the underlying CSS box model and rendering engine (and physical/writing-mode-relative layout coordinates) anchor box positions by their *start* edge (e.g., `inline-start` / `block-start` in logical coordinates, or top-left in physical coordinates) rather than their *end* edge.

When `flex-direction` is `row-reverse` or `column-reverse`:
1. The flex layout algorithm computes item advancements along the abstract **flex main axis** starting from $0$ at the *main-start* edge.
2. Let $C$ be the main-axis inner size of the flex container (`container_size`).
3. Let an item have a main-axis margin-box or border-box size $S$ (`item_size`) and a computed distance $x$ (`offset`) from the *main-start* edge to the item's *main-start* edge.
4. Consequently, the item occupies the interval $[x, x + S]$ relative to *main-start*.
5. Since *main-start* coincides with the container's logical *end* edge (either `inline-end` for `row-reverse` or `block-end` for `column-reverse`), the distance from the container's logical *start* edge (`inline-start` or `block-start`) to the item's logical *start* edge (which is its *main-end* edge, located at distance $x + S$ from *main-start*) is exactly:
   $$x' = C - (x + S) = C - x - S$$

This exact affine involution is the normative basis for `row-reverse` and `column-reverse` coordinate mirroring.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium Blink’s LayoutNG architecture, flex layout is implemented in `third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc`.

### 2.1 Logical Coordinate Space vs. Flex-Relative Coordinate Space
Blink’s LayoutNG operates primarily in a **Writing-Mode Logical Coordinate System** (`LogicalOffset`, `LogicalSize`), where:
* `inline_offset` increases from `inline-start` to `inline-end`.
* `block_offset` increases from `block-start` to `block-end`.

When `FlexLayoutAlgorithm::GiveItemsFinalPositionAndSize()` and `GiveItemsFinalPositionAndSizeForFragmentation()` execute:
1. Items are first laid out along a monotonically increasing cursor `main_axis_offset` starting from the main-start border/padding edge.
2. Each `FlexItem` (and its output `NGFlexItem` / `FlexLine`) records its `main_axis_offset` in flex-flow relative coordinates.
3. Before adding the fragment to `container_builder_` via `container_builder_.AddResult(...)`, Blink translates the flex-relative offset into the container's `LogicalOffset`.

### 2.2 C++ Implementation in `flex_layout_algorithm.cc`
In `FlexLayoutAlgorithm::PlaceFlexItems()` and `FlexLayoutAlgorithm::GiveItemsFinalPositionAndSize()`:

```cpp
// Simplified excerpt from third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc
LayoutUnit main_axis_offset = ...; // Computed from main-start (includes justify-content, margins, etc.)

// When translating to LogicalOffset (inline_offset, block_offset):
if (is_column_) {
  offset.inline_offset = cross_axis_offset;
  if (is_reverse_direction) {
    offset.block_offset = main_axis_inner_size - main_axis_offset - item_main_axis_size;
  } else {
    offset.block_offset = main_axis_offset;
  }
} else {
  offset.block_offset = cross_axis_offset;
  if (is_reverse_direction) {
    offset.inline_offset = main_axis_inner_size - main_axis_offset - item_main_axis_size;
  } else {
    offset.inline_offset = main_axis_offset;
  }
}
```
*(Note: When border and scrollbar/padding offsets are separated from `main_axis_inner_size`, the border/padding sum Equals `main_axis_start_offset + main_axis_end_offset`, preserving the exact algebraic form `total_container_main_size - main_axis_offset - item_size` within the content box).*

### 2.3 Core Blink Layout Invariants
1. **Duality / Involution (`reverse_offset_involution`)**: Applying the reverse transformation twice restores the original offset:
   $$\text{reverse\_offset}(\text{reverse\_offset}(x, S, C), S, C) = x$$
2. **Containment Preservation (`reverse_offset_in_bounds`)**: If a flex item of non-negative size $S \ge 0$ lies completely within the container $[0, C]$ in flex-space ($0 \le x$ and $x + S \le C$), then its mirrored logical interval $[x', x' + S]$ also lies completely within $[0, C]$ ($0 \le x'$ and $x' + S \le C$).
3. **Boundary Mapping**: An item flushed against `main-start` ($x = 0$) is mapped to $C - S$ (so its trailing edge touches $C$). An item flushed against `main-end` ($x = C - S$) is mapped to $0$ (flushed against logical start).
4. **Gap & Adjacency Preservation (`reverse_gap_preservation`)**: If Item 1 is followed by Item 2 in flex order with a separation gap $g = x_2 - (x_1 + S_1)$, then after mirroring, Item 2 precedes Item 1 in logical coordinates with the exact same gap $g = x'_1 - (x'_2 + S_2)$. In particular, non-overlapping items remain non-overlapping.
5. **Cross-Axis Independence**: Reversing the main axis leaves the cross-axis coordinate completely invariant.

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained, and admitted-free Rocq formalization `BlinkFlexReverseLayoutCoordinateMirroringSemantics.v`. It formalizes 1D main-axis transformations, 2D logical coordinates (`row`, `row-reverse`, `column`, `column-reverse`), interval geometry, and list-based sequential flex line layout.

```coq
(** * BlinkFlexReverseLayoutCoordinateMirroringSemantics.v
    Formal Verification of W3C CSS Flexbox §5.1 & §9 Coordinate Mirroring
    Target: third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc
    Agent: 686 (W3C/WHATWG Layout Rules in Chromium Blink)
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Definitions *)

(** In Blink, LayoutUnit is a fixed-point integer representation (1/64th of a pixel).
    We model LayoutUnit arithmetic over integer rings [Z]. *)
Definition LayoutUnit := Z.

(** CSS Flexbox §5.1 flex-direction values *)
Inductive FlexDirection : Type :=
  | FlexRow           (* main-axis: inline, forward *)
  | FlexRowReverse    (* main-axis: inline, reverse *)
  | FlexColumn        (* main-axis: block,  forward *)
  | FlexColumnReverse (* main-axis: block,  reverse *).

(** Predicates corresponding to Blink's [is_column_] and [is_reverse_direction] *)
Definition is_column (dir : FlexDirection) : bool :=
  match dir with
  | FlexColumn | FlexColumnReverse => true
  | FlexRow | FlexRowReverse => false
  end.

Definition is_reverse (dir : FlexDirection) : bool :=
  match dir with
  | FlexRowReverse | FlexColumnReverse => true
  | FlexRow | FlexColumn => false
  end.

(** Logical 2D offset in Blink (inline_offset, block_offset) *)
Record LogicalOffset : Type := mkLogicalOffset {
  inline_offset : LayoutUnit;
  block_offset  : LayoutUnit
}.

(** Logical 2D size in Blink (inline_size, block_size) *)
Record LogicalSize : Type := mkLogicalSize {
  inline_size : LayoutUnit;
  block_size  : LayoutUnit
}.

(** Representation of a positioned flex item in flex-relative coordinates *)
Record FlexItem : Type := mkFlexItem {
  item_main_offset  : LayoutUnit;
  item_cross_offset : LayoutUnit;
  item_main_size    : LayoutUnit;
  item_cross_size   : LayoutUnit
}.

(** ** 2. Core Coordinate Mirroring Function *)

(** Mathematical Property:
    reverse_offset(offset, item_size, container_size) = container_size - offset - item_size *)
Definition reverse_offset (offset item_size container_size : LayoutUnit) : LayoutUnit :=
  container_size - offset - item_size.

(** Conditional main-axis offset resolver based on directionality *)
Definition resolve_main_offset (rev : bool) (offset item_size container_size : LayoutUnit) : LayoutUnit :=
  if rev then reverse_offset offset item_size container_size
  else offset.

(** Full 2D LogicalOffset translation as implemented in
    [FlexLayoutAlgorithm::GiveItemsFinalPositionAndSize] *)
Definition to_logical_offset
  (dir : FlexDirection)
  (container_main_size : LayoutUnit)
  (item : FlexItem) : LogicalOffset :=
  let main_pos :=
    resolve_main_offset
      (is_reverse dir)
      (item_main_offset item)
      (item_main_size item)
      container_main_size in
  if is_column dir then
    mkLogicalOffset (item_cross_offset item) main_pos
  else
    mkLogicalOffset main_pos (item_cross_offset item).

(** Well-formedness and containment predicates *)
Definition in_bounds (offset item_size container_size : LayoutUnit) : Prop :=
  0 <= item_size /\
  0 <= offset /\
  offset + item_size <= container_size.

Definition intervals_disjoint (o1 s1 o2 s2 : LayoutUnit) : Prop :=
  o1 + s1 <= o2 \/ o2 + s2 <= o1.

(** ** 3. Fundamental Algebraic and Geometric Theorems *)

(** Theorem 1: Mirroring is a strict involution.
    Applying [reverse_offset] twice yields the original offset. *)
Theorem reverse_offset_involution :
  forall (offset item_size container_size : LayoutUnit),
    reverse_offset (reverse_offset offset item_size container_size) item_size container_size = offset.
Proof.
  intros offset item_size container_size.
  unfold reverse_offset.
  lia.
Qed.

(** Theorem 2: [resolve_main_offset] applied twice with the same boolean flag is an involution. *)
Theorem resolve_main_offset_involution :
  forall (rev : bool) (offset item_size container_size : LayoutUnit),
    resolve_main_offset rev
      (resolve_main_offset rev offset item_size container_size)
      item_size container_size = offset.
Proof.
  intros rev offset item_size container_size.
  destruct rev; simpl.
  - apply reverse_offset_involution.
  - reflexivity.
Qed.

(** Theorem 3: Boundary Mapping at Main-Start.
    An item placed at main-start (offset = 0) is placed at (container_size - item_size),
    meaning its end edge aligns exactly with container_size. *)
Theorem reverse_offset_at_main_start :
  forall (item_size container_size : LayoutUnit),
    reverse_offset 0 item_size container_size + item_size = container_size.
Proof.
  intros item_size container_size.
  unfold reverse_offset.
  lia.
Qed.

(** Theorem 4: Boundary Mapping at Main-End.
    An item touching main-end (offset = container_size - item_size) is mapped to 0. *)
Theorem reverse_offset_at_main_end :
  forall (item_size container_size : LayoutUnit),
    reverse_offset (container_size - item_size) item_size container_size = 0.
Proof.
  intros item_size container_size.
  unfold reverse_offset.
  lia.
Qed.

(** Theorem 5: Containment Invariance.
    An item within [0, container_size] remains within [0, container_size] after mirroring. *)
Theorem reverse_offset_preserves_bounds :
  forall (offset item_size container_size : LayoutUnit),
    in_bounds offset item_size container