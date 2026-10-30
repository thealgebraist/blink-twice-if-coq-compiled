# Formal Verification Report: Flex Cross-Axis Stretch Alignment under Min/Max Bounds

**Agent:** 688 (W3C/WHATWG Layout Rules — Chromium Blink)  
**Target Source:** `third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc`  
**Specification:** CSS Flexible Box Layout Module Level 1, §9.4 (Cross Size Determination)  
**Formal Theory Target:** `BlinkFlexboxCrossAxisStretchMinMaxClampingSemantics.v`  
**Core Mathematical Property:**  
$$\text{stretched\_cross}(\text{line\_cross}, \text{min\_c}, \text{max\_c}) = \max(\text{min\_c}, \min(\text{line\_cross}, \text{max\_c}))$$

---

## 1. Normative W3C CSS Flexbox Specification Requirements

In the CSS Flexible Box Layout Module Level 1 (W3C Candidate Recommendation), **§9.4 Cross Size Determination** defines the algorithm for resolving the used cross size of each flex line and its constituent flex items. Specifically, **Step 11** governs items with `stretch` alignment:

> **CSS Flexbox 1 §9.4, Step 11:**  
> Determine the used cross size of each flex item. If a flex item has `align-self: stretch`, its computed cross size property is `auto`, and neither of its cross-axis margins are `auto`, the used outer cross size is the used cross size of its flex line, clamped according to the item's used min and max cross size properties. Otherwise, the used cross size is the item's hypothetical cross size.

### 1.1 Normative Preconditions for Cross-Axis Stretch
For a flex item $i$ residing on a flex line $L$ with resolved cross size $C_L$, cross-axis stretching applies if and only if all of the following predicates hold:
1. **Computed Alignment:** The resolved `align-self` value for $i$ (inheriting from the container's `align-items` if `align-self: auto`) is `normal` or `stretch`.
2. **Auto Cross-Size:** The item's computed cross-axis size property (`height` in horizontal `row` flex containers; `width` in vertical `column` flex containers) is `auto` (and is not overridden by an explicit aspect-ratio transfer unless stretched into the ratio).
3. **Non-Auto Cross Margins:** Neither the cross-start margin (`margin-top` / `margin-left`) nor the cross-end margin (`margin-bottom` / `margin-right`) is `auto`. (Per §8.1, `auto` cross margins absorb free space and suppress `stretch`, forcing the item to fall back to `flex-start` alignment).

### 1.2 Clamping Precedence (CSS Sizing 3 & CSS 2.1 §10.4 / §10.7)
When clamping a target cross border-box size $S_{\text{target}} = C_L - M_{\text{cross}}$ (where $M_{\text{cross}}$ is the sum of resolved non-auto cross margins) against minimum bound $\text{min\_c}$ and maximum bound $\text{max\_c}$, CSS specification mandates **min-wins-over-max** precedence:
$$\text{clamp}(x, \text{min\_c}, \text{max\_c}) = \max(\text{min\_c}, \min(x, \text{max\_c}))$$
If $\text{min\_c} > \text{max\_c}$, the resolved used cross size equals $\text{min\_c}$. Furthermore, border and padding sums ($BP_{\text{cross}}$) act as an implicit floor on border-box dimensions under `box-sizing: content-box` or `border-box`.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's LayoutNG architecture, flex layout is orchestrated by `FlexLayoutAlgorithm` in `third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc` alongside `NGFlexLine` and `FlexItem` structures.

### 2.1 Code Path Analysis in `flex_layout_algorithm.cc`

During `FlexLayoutAlgorithm::GiveItemsFinalPositionAndSize()` and `ApplyStretchAlignmentToChild()`, Blink executes the following steps:

```cpp
// Conceptual extraction from third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc
bool FlexLayoutAlgorithm::DoesItemStretch(const FlexItem& flex_item) const {
  if (flex_item.AlignSelf() != ItemPosition::kStretch)
    return false;
  if (flex_item.HasAutoMarginsInCrossAxis())
    return false;
  return WillChildCrossSizeBeContainerCrossSize(flex_item.ng_input_node_);
}
```

When `DoesItemStretch(flex_item)` evaluates to `true`, Blink computes the stretched border-box cross size:

```cpp
LayoutUnit line_cross_size = line_output.cross_size;
LayoutUnit available_cross_size =
    (line_cross_size - flex_item.CrossAxisMarginExtent()).ClampNegativeToZero();

// MinMaxSizes struct holds {min_size, max_size} in border-box coordinates.
// MinMaxSizes::ClampSizeToMinAndMax(LayoutUnit size) implements:
//   return std::max(min_size, std::min(size, max_size));
LayoutUnit stretched_cross_size =
    flex_item.min_max_cross_sizes_.ClampSizeToMinAndMax(available_cross_size);
```

This clamped value is then written into the child's `ConstraintSpaceBuilder` via `SetAvailableSize` and `SetIsFixedInlineSize` / `SetIsFixedBlockSize` (depending on whether the flex container is `column` or `row`), triggering a relayout of the flex item if `stretched_cross_size != flex_item.cross_axis_size_`.

### 2.2 Core Blink Layout Invariants
1. **Min-Dominance Invariant:** `MinMaxSizes::ClampSizeToMinAndMax(val)` guarantees `result >= min_size` unconditionally, even when `min_size > max_size`.
2. **Non-Negativity Invariant:** Since `min_size >= border_padding >= 0` and `available_cross_size >= 0`, the resulting `stretched_cross_size` is strictly non-negative (`>= 0`).
3. **Hypothetical Pre-Clamping Invariant:** If an item does *not* stretch, its hypothetical cross size `flex_item.cross_axis_size_` was already clamped by `min_max_cross_sizes_` during `ConstructAndAppendFlexItems()`.
4. **Idempotence of Relayout Clamping:** Re-clamping an already stretched and clamped cross size against the identical `MinMaxSizes` is a strict no-op.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization target `BlinkFlexboxCrossAxisStretchMinMaxClampingSemantics.v`. It models CSS Flexbox 1 §9.4 Step 11 and Blink's `MinMaxSizes::ClampSizeToMinAndMax` semantics over arbitrary-precision integers (`Z`, representing Blink's fixed-point `LayoutUnit` raw quanta).

```coq
(** * BlinkFlexboxCrossAxisStretchMinMaxClampingSemantics.v
    Formal Verification of W3C CSS Flexbox 1 §9.4 Cross-Size Stretch Determination
    and Min/Max Clamping in Chromium Blink (flex_layout_algorithm.cc). *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Enumerations *)

(** Alignment positions corresponding to Blink's [ItemPosition] in ComputedStyleConstants.h *)
Inductive AlignSelf : Type :=
  | AlignAuto
  | AlignNormal
  | AlignStretch
  | AlignFlexStart
  | AlignFlexEnd
  | AlignCenter
  | AlignBaseline.

(** Cross-axis computed length property representation *)
Inductive CrossSizeSpec : Type :=
  | CrossSizeAuto
  | CrossSizeFixed (px : Z).

(** Optional upper bound for max-height / max-width ('none' vs '<length>') *)
Inductive MaxBound : Type :=
  | MaxNone
  | MaxFixed (px : Z).

(** MinMaxSizes border-box bounds as resolved in Blink [MinMaxSizes] *)
Record MinMaxCrossBounds : Type := mkMinMax {
  min_cross : Z;
  max_cross : MaxBound
}.

(** Cross-axis margin configuration *)
Record CrossMargins : Type := mkCrossMargins {
  margin_start_auto : bool;
  margin_end_auto   : bool;
  margin_start_val  : Z;
  margin_end_val    : Z
}.

(** Flex Item model capturing layout inputs for §9.4 Step 11 *)
Record FlexItem : Type := mkFlexItem {
  item_align_self        : AlignSelf;
  item_cross_size_spec   : CrossSizeSpec;
  item_cross_margins     : CrossMargins;
  item_bounds            : MinMaxCrossBounds;
  item_border_padding    : Z;
  item_intrinsic_cross   : Z
}.

(** ** 2. Helper Functions & Blink Primitives *)

(** Blink's [LayoutUnit::ClampNegativeToZero()] *)
Definition clamp_negative_to_zero (x : Z) : Z :=
  Z.max 0 x.

(** Core mathematical property:
    stretched_cross(line_cross, min_c, max_c) = max(min_c, min(line_cross, max_c)) *)
Definition stretched_cross (line_cross min_c max_c : Z) : Z :=
  Z.max min_c (Z.min line_cross max_c).

(** Blink's [MinMaxSizes::ClampSizeToMinAndMax] supporting unbounded max (LayoutUnit::Max() / none) *)
Definition clamp_to_bounds (size : Z) (b : MinMaxCrossBounds) : Z :=
  match max_cross b with
  | MaxNone => Z.max (min_cross b) size
  | MaxFixed max_c => stretched_cross size (min_cross b) max_c
  end.

(** Sum of resolved cross-axis margins (auto margins evaluate to 0 during size determination) *)
Definition cross_margin_extent (m : CrossMargins) : Z :=
  let s := if margin_start_auto m then 0 else margin_start_val m in
  let e := if margin_end_auto m then 0 else margin_end_val m in
  s + e.

(** Predicate: Does the item have any auto cross-axis margin? *)
Definition has_auto_cross_margins (m : CrossMargins) : bool :=
  orb (margin_start_auto m) (margin_end_auto m).

(** Effective align-self resolution given container's align-items *)
Definition resolve_align_self (item_align container_align : AlignSelf) : AlignSelf :=
  match item_align with
  | AlignAuto => container_align
  | other     => other
  end.

(** Blink's [WillChildCrossSizeBeContainerCrossSize] & [DoesItemStretch] *)
Definition does_item_stretch (item : FlexItem) (container_align : AlignSelf) : bool :=
  let eff_align := resolve_align_self (item_align_self item) container_align in
  let is_stretch_align :=
    match eff_align with
    | AlignStretch | AlignNormal => true
    | _ => false
    end in
  let is_auto_size :=
    match item_cross_size_spec item with
    | CrossSizeAuto => true
    | CrossSizeFixed _ => false
    end in
  andb is_stretch_align (andb is_auto_size (negb (has_auto_cross_margins (item_cross_margins item)))).

(** Base un-clamped cross size prior to §9.4 Step 11 *)
Definition base_cross_size (item : FlexItem) : Z :=
  match item_cross_size_spec item with
  | CrossSizeAuto => item_intrinsic_cross item
  | CrossSizeFixed px => px
  end.

(** Hypothetical cross size (§9.4 Step 7): base size clamped to min/max bounds *)
Definition hypothetical_cross_size (item : FlexItem) : Z :=
  clamp_to_bounds (base_cross_size item) (item_bounds item).

(** Available outer cross size subtracted by cross margins, clamped >= 0 *)
Definition available_stretched_border_box (line_cross : Z) (m : CrossMargins) : Z :=
  clamp_negative_to_zero (line_cross - cross_margin_extent m).

(** Final used cross border-box size (§9.4 Step 11 & Blink GiveItemsFinalPositionAndSize) *)
Definition used_cross_size (item : FlexItem) (container_align : AlignSelf) (line_cross : Z) : Z :=
  if does_item_stretch item container_align then
    let target := available_stretched_border_box line_cross (item_cross_margins item) in
    clamp_to_bounds target (item_bounds item)
  else
    hypothetical_cross_size item.

(** Well-formedness invariants on layout inputs *)
Definition wf_bounds (b : MinMaxCrossBounds) (bp : Z) : Prop :=
  0 <= bp /\
  bp <= min_cross b /\
  match max_cross b with
  | MaxNone => True
  | MaxFixed max_c => bp <= max_c
  end.

Definition wf_flex_item (item : FlexItem) : Prop :=
  wf_bounds (item_bounds item) (item_border_padding item) /\
  0 <= item_intrinsic_cross item.
```

---

## 4. Concrete Theorems and Complete Proofs

All theorems below are proven without `admit` or `Admitted`, using standard `ZArith`, `Lia`, `Bool`, and `List` tactics.

```coq
(** ** 3. Formal Theorems and Proofs *)

(** Theorem 1: Fundamental Lower Bound (Min-Dominance).
    Regardless of whether min_c <= max_c or min_c > max_c,
    stretched_cross is always at least min_c. *)
Theorem stretched_cross_ge_min :
  forall line_cross min_c max_c : Z,
    min_c <= stretched_cross line_cross min_c max_c.
Proof.
  intros line_cross min_c max_c.
  unfold stretched_cross.
  lia.
Qed.

(** Theorem 2: Upper Bound under Well-Ordered Min/Max.
    When min_c <= max_c, stretched_cross never exceeds max_c. *)
Theorem stretched_cross_le_max :
  forall line_cross min_c max_c : Z,
    min_c <= max_c ->
    stretched_cross line_cross min_c max_c <= max_c.
Proof.
  intros line_cross min_c max_c Hle.