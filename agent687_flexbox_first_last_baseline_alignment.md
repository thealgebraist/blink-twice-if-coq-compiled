# Formal Verification Report: Flex Container First and Last Baseline Alignment
**Agent:** 687 (W3C/WHATWG Layout Rules — Chromium Blink)  
**Target Source:** `third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc`  
**Specification:** CSS Flexible Box Layout Module Level 1 (§8.3 Cross-axis Alignment: the `align-items` and `align-self` properties) & CSS Box Alignment Module Level 3 (§9 Baseline Alignment Details)  
**Formal Theory Target:** `BlinkFlexboxFirstLastBaselineAlignmentSemantics.v`  
**Core Mathematical Invariant:** $\forall \text{item} \in \text{group}, \quad \text{baseline\_offset}(\text{item}_b, \max_b) = \max_b - \text{item}_b \ge 0$

---

## 1. Normative W3C Specification Requirements

### 1.1 CSS Flexbox 1 §8.3 (`align-items` and `align-self`: `baseline` / `last baseline`)
According to the W3C CSS Flexible Box Layout Module Level 1 (§8.3) and CSS Box Alignment Module Level 3 (§9):
1. **Baseline-Sharing Group Formation**: A flex item participates in **first** (`baseline`) or **last** (`last baseline`) baseline alignment within its flex line if its computed `align-self` is `baseline` or `last baseline` respectively, and its cross-axis inline-axis orientation is parallel to the flex container's main axis (i.e., the item's baseline axis is parallel to the main axis), or via synthesized orthogonal baselines as defined in CSS Alignment 3.
2. **Alignment Context**: Within a single flex line, all items specifying `first baseline` (and sharing the same baseline alignment context direction) form a *first-baseline-sharing group*. All items specifying `last baseline` form a *last-baseline-sharing group*.
3. **Group Placement & Cross-Axis Offset Calculation**:
   - **First Baseline (`baseline`)**: The items in the group are aligned such that their first baselines coincide. The group as a whole is positioned at the cross-start edge of the flex line. Specifically, let $B_{\text{first}}(i)$ be the distance from item $i$'s outer cross-start margin edge to its first baseline. The maximum baseline distance across the group is:
     $$M_{\text{first}} = \max_{i \in G_{\text{first}}} B_{\text{first}}(i)$$
     Each item $i \in G_{\text{first}}$ is shifted from the flex line's cross-start edge by:
     $$\text{offset}_{\text{cross-start}}(i) = M_{\text{first}} - B_{\text{first}}(i) \ge 0$$
   - **Last Baseline (`last baseline`)**: The items in the group are aligned such that their last baselines coincide, and the group is positioned flush against the cross-end edge of the flex line. Let $H(i)$ be the outer cross-size (margin box cross size) of item $i$, and $B_{\text{last}}^{\text{start}}(i)$ be the distance from item $i$'s outer cross-start edge to its last baseline. The distance from the outer cross-end edge to the last baseline (the *under-baseline* or *descent* metric) is:
     $$D_{\text{last}}(i) = H(i) - B_{\text{last}}^{\text{start}}(i)$$
     Let the maximum descent across the last-baseline group be:
     $$M_{\text{last}} = \max_{i \in G_{\text{last}}} D_{\text{last}}(i)$$
     Each item $i \in G_{\text{last}}$ is shifted inward from the flex line's cross-end edge by $\text{offset}_{\text{cross-end}}(i) = M_{\text{last}} - D_{\text{last}}(i) \ge 0$. Consequently, given a flex line cross size $S_{\text{line}}$, the cross-start offset of item $i$ is:
     $$\text{offset}_{\text{cross-start}}(i) = S_{\text{line}} - M_{\text{last}} - B_{\text{last}}^{\text{start}}(i) = S_{\text{line}} - H(i) - (M_{\text{last}} - D_{\text{last}}(i))$$
4. **Line Cross-Size Contribution**: The baseline-sharing group's combined ascent + descent contributes to the flex line's cross size:
   $$S_{\text{line}} \ge \max\left( \max_{i \in G_{\text{first}}} B_{\text{first}}(i) + \max_{i \in G_{\text{first}}} (H(i) - B_{\text{first}}(i)), \quad \max_{i \in G_{\text{last}}} B_{\text{last}}^{\text{start}}(i) + \max_{i \in G_{\text{last}}} D_{\text{last}}(i) \right)$$

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink's LayoutNG architecture (`third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc` and `flex_line.h` / `ng_flex_item_iterator.h`):

### 2.1 Baseline Ascent Calculation (`FlexItem::MarginBoxAscent`)
When `FlexLayoutAlgorithm::ConstructAndAppendFlexItems` and `GiveItemsFinalPositionAndSize` execute:
- Each `FlexItem` computes its margin-box baseline distance via `MarginBoxAscent(bool is_last_baseline, bool is_wrap_reverse)`:
  ```cpp
  LayoutUnit FlexItem::MarginBoxAscent(bool is_last_baseline, bool is_wrap_reverse) const {
    LayoutUnit ascent = Baseline(is_last_baseline); // From PhysicalBoxFragment::FirstBaseline() or LastBaseline()
    if (is_last_baseline != is_wrap_reverse)
      ascent = cross_axis_size_ - ascent;
    return ascent + ((is_last_baseline != is_wrap_reverse) ? margin_block_end : margin_block_start);
  }
  ```
- Notice the unified symmetric formulation in Blink:
  - For **First Baseline** (assuming normal wrap `is_wrap_reverse == false`): `MarginBoxAscent` returns the distance from the margin-box cross-start edge to the first baseline ($B_{\text{first}}(i)$).
  - For **Last Baseline** (`is_last_baseline == true`, `is_wrap_reverse == false`): `MarginBoxAscent` inverts the coordinate to measure from the margin-box cross-end edge to the last baseline ($D_{\text{last}}(i) = H(i) - B_{\text{last}}^{\text{start}}(i)$).

### 2.2 Line Accumulation (`max_major_ascent` and `max_minor_ascent`)
During line construction and cross-axis sizing (`FlexLayoutAlgorithm::GiveItemsFinalPositionAndSize`):
- Blink tracks two maximum ascents per `NGFlexLine`:
  - `max_major_ascent_`: Maximum `MarginBoxAscent` for items aligned to the cross-start baseline (`kBaseline` when not `wrap-reverse`).
  - `max_minor_ascent_`: Maximum `MarginBoxAscent` for items aligned to the cross-end baseline (`kLastBaseline` when not `wrap-reverse`).
- For each item $i$ on the flex line:
  ```cpp
  if (flex_item.Alignment() == ItemPosition::kBaseline ||
      flex_item.Alignment() == ItemPosition::kLastBaseline) {
    bool is_last_baseline = flex_item.Alignment() == ItemPosition::kLastBaseline;
    LayoutUnit ascent = flex_item.MarginBoxAscent(is_last_baseline, is_wrap_reverse);
    LayoutUnit descent = flex_item.cross_axis_size_ - ascent;
    if (is_last_baseline == is_wrap_reverse) {
      max_major_ascent = std::max(max_major_ascent, ascent);
      max_major_descent = std::max(max_major_descent, descent);
    } else {
      max_minor_ascent = std::max(max_minor_ascent, ascent);
      max_minor_descent = std::max(max_minor_descent, descent);
    }
  }
  ```
- The line's cross size (`line_cross_size`) is clamped to at least `std::max(max_major_ascent + max_major_descent, max_minor_ascent + max_minor_descent)`.

### 2.3 Final Cross-Axis Offset (`baseline_offset`)
When computing the final cross-axis offset of a baseline-aligned item within a line of size `line_cross_size`:
1. **Major Baseline (`kBaseline` in non-wrap-reverse)**:
   $$\text{baseline\_offset}(i) = \text{max\_major\_ascent} - \text{ascent}(i)$$
   Since $\text{max\_major\_ascent} = \max_{j \in G_{\text{major}}} \text{ascent}(j)$, we have $\text{baseline\_offset}(i) \ge 0$.
2. **Minor Baseline (`kLastBaseline` in non-wrap-reverse)**:
   The distance from the cross-end of the line is $\text{end\_offset}(i) = \text{max\_minor\_ascent} - \text{ascent}(i) \ge 0$.
   The distance from the cross-start of the line is:
   $$\text{cross\_offset}(i) = \text{line\_cross\_size} - \text{cross\_axis\_size}(i) - (\text{max\_minor\_ascent} - \text{ascent}(i))$$

### 2.4 Container First/Last Baseline Propagation (`PropagateBaselineFromChild`)
Once all flex items are positioned, the flex container itself exports a first baseline and a last baseline to its parent formatting context:
1. **Container First Baseline**:
   - If the **first flex line** has any item participating in first-baseline alignment (`Alignment() == kBaseline` and non-auto cross margins), the container's first baseline is the aligned baseline of that group (i.e., `first_line_cross_offset + max_major_ascent`).
   - Otherwise, if the container has at least one flex item, it falls back to the first baseline (or synthesized baseline) of the first flex item on the first line.
2. **Container Last Baseline**:
   - If the **last flex line** has any item participating in last-baseline alignment (`Alignment() == kLastBaseline` and non-auto cross margins), the container's last baseline is the aligned baseline of that group on the last line.
   - Otherwise, if the container has at least one flex item, it falls back to the last baseline of the last flex item on the last line.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained, and admitted-free Rocq/Coq formalization (`BlinkFlexboxFirstLastBaselineAlignmentSemantics.v`). It models `LayoutUnit` arithmetic over $\mathbb{Z}$, baseline-sharing groups, `MarginBoxAscent`, major/minor baseline accumulators, item offset placement, flex line cross-size bounds, and container-level first/last baseline propagation.

```coq
(** * BlinkFlexboxFirstLastBaselineAlignmentSemantics.v
    Formal Verification of W3C CSS Flexbox §8.3 & Chromium Blink
    Flex Container First and Last Baseline Alignment
    Target: third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import List.
From Coq Require Import Bool.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Layout Types and Alignment Enumerations *)

(** In Blink, LayoutUnit is a fixed-point type modeled over Z. *)
Definition LayoutUnit := Z.

(** CSS align-self / align-items values relevant to Flexbox cross-axis alignment. *)
Inductive ItemPosition : Type :=
  | kFlexStart
  | kFlexEnd
  | kCenter
  | kStretch
  | kBaseline
  | kLastBaseline.

Scheme Equality for ItemPosition.

(** Representation of a FlexItem after fragment generation during flex layout. *)
Record FlexItem : Type := mkFlexItem {
  item_id : nat;
  alignment : ItemPosition;
  has_auto_cross_margin : bool;
  margin_cross_start : LayoutUnit;
  margin_cross_end : LayoutUnit;
  border_box_cross_size : LayoutUnit;
  (** Distance from border-box cross-start to first baseline *)
  first_baseline_from_border_start : LayoutUnit;
  (** Distance from border-box cross-start to last baseline *)
  last_baseline_from_border_start : LayoutUnit
}.

(** Total outer (margin-box) cross size of a flex item. *)
Definition margin_box_cross_size (item : FlexItem) : LayoutUnit :=
  margin_cross_start item + border_box_cross_size item + margin_cross_end item.

(** Well-formedness predicate for a FlexItem's geometry. *)
Definition wf_flex_item (item : FlexItem) : Prop :=
  0 <= border_box_cross_size item /\
  0 <= margin_box_cross_size item /\
  0 <= margin_cross_start item + first_baseline_from_border_start item /\
  margin_cross_start item + first_baseline_from_border_start item <= margin_box_cross_size item /\
  0 <= margin_cross_start item + last_baseline_from_border_start item /\
  margin_cross_start item + last_baseline_from_border_start item <= margin_box_cross_size item.

(** ** 2. Blink MarginBoxAscent and MarginBoxDescent Semantics *)

(** Models FlexItem::MarginBoxAscent(bool is_last_baseline, bool is_wrap_reverse).
    - When is_last_baseline != is_wrap_reverse is false (Major baseline: e.g., First Baseline in normal wrap):
      measures distance from margin-box cross-start to baseline.
    - When is_last_baseline != is_wrap_reverse is true (Minor baseline: e.g., Last Baseline in normal wrap):
      measures distance from margin-box cross-end to baseline. *)
Definition margin_box_ascent (item : FlexItem) (is_last_baseline : bool) (is_wrap_reverse : bool) : LayoutUnit :=
  let raw_baseline :=
    if is_last_baseline
    then last_baseline_from_border_start item
    else first_baseline_from_border_start item
  in
  let from_margin_start := margin_cross_start item + raw_baseline in
  if Bool.eqb is_last_baseline is_wrap_reverse
  then from_margin_start
  else margin_box_cross_size item - from_margin_start.

Definition margin_box_descent (item : FlexItem) (is_last_baseline : bool) (is_wrap_reverse : bool) : LayoutUnit :=
  margin_