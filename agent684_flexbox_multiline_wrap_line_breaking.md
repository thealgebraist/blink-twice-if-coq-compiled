# Formal Verification Report: Multiline Flexbox Line Breaking and Cross-Size Distribution in Chromium Blink

**Agent ID:** 684 (W3C/WHATWG Layout Verification Specialist)  
**Target Component:** `third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc`  
**Specification:** CSS Flexible Box Layout Module Level 1 (W3C Candidate Recommendation), Section 9.3 & 9.4  
**Formal Artifact:** `BlinkFlexboxMultilineWrapLineBreakingSemantics.v`  
**Core Invariant:** `new_line_created(sum_hypothetical, avail) = (sum_hypothetical > avail && count > 0)`  

---

## 1. Normative W3C CSS Flexbox Specification Requirements

The layout of multiline flexible boxes is governed by **CSS Flexible Box Layout Module Level 1, Section 9 (Flex Layout Algorithm)**. Specifically, line breaking and cross-axis distribution are defined in **Section 9.3 (Main Size Determination)** and **Section 9.4 (Cross Size Determination)**.

### 1.1. Section 9.3 Step 5: Collect Flex Items into Flex Lines
When a flex container has `flex-wrap: wrap` or `flex-wrap: wrap-reverse` (making it *multi-line*), its in-flow flex items are partitioned into contiguous subsequences called **flex lines** according to the following normative algorithm:

1. **Initialization:** Collect flex items into flex lines starting from the first item in order-modified document order.
2. **Accumulation & Overflow Condition:** For each subsequent item, calculate its **outer hypothetical main size** (the item's clamped flex base size plus its main-axis margins, borders, and padding). Add this value (along with any main-axis `gap` between items) to the running sum of outer hypothetical main sizes of items already collected onto the current flex line.
3. **Line Breaking Predicate:** If the running sum exceeds the flex container's **available main space** (`avail`), a line break occurs *before* the current item, initiating a new flex line.
4. **Non-Empty Line Exception (Progress Guarantee):** *If a single flex item's outer hypothetical main size is larger than the flex container's available main space, it is placed on its own flex line rather than forcing an empty line before it.* Formally, a line break only occurs if the current flex line already contains at least one item (`count > 0`).
5. **Forced Breaks:** Items with `break-before` or `break-after` properties force a line break immediately before or after the item respectively, regardless of available space.

### 1.2. Section 9.4: Cross Size Determination
Once items are partitioned into lines $L_1, L_2, \dots, L_k$:
1. **step 7:** Determine the hypothetical cross size of each item by performing layout with its used main size.
2. **Step 8:** Calculate the cross size of each flex line $L_i$. For a multi-line container, the line cross size is the maximum of:
   - The largest distance between the baseline and cross-start margin edge plus the largest distance between the baseline and cross-end margin edge among baseline-aligned items in $L_i$.
   - The largest outer hypothetical cross size among all other items in $L_i$.
3. **Step 9 (`align-content: stretch`):** If the flex container has a definite cross size $C_{\text{def}}$ and `align-content` is `stretch`, if the sum of the cross sizes of all flex lines (plus cross-axis gaps) is less than $C_{\text{def}}$, the leftover free cross space $\Delta C = C_{\text{def}} - \sum \text{cross\_size}(L_i) - \text{gaps}$ is distributed equally among all $k$ flex lines:
   $$\forall i \in \{1..k\}, \quad \text{cross\_size}'(L_i) = \text{cross\_size}(L_i) + \frac{\Delta C}{k}$$

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink's LayoutNG architecture, the core state machine for flexbox line construction resides in `third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc` (and its associated header `flexible_box_algorithm.h`).

### 2.1. Code Path: `FlexLayoutAlgorithm::ComputeNextFlexLine`

Blink decouples the mathematical flexbox specification from DOM/LayoutObject specifics via `FlexLayoutAlgorithm`, `FlexItem`, and `FlexLine`.

```cpp
// Simplified representation of third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc
FlexLine* FlexLayoutAlgorithm::ComputeNextFlexLine(
    LayoutUnit container_logical_width) {
  Vector<FlexItem> line_items;
  LayoutUnit sum_flex_base_size;
  double total_flex_grow = 0;
  double total_flex_shrink = 0;
  double total_weighted_flex_shrink = 0;
  LayoutUnit sum_hypothetical_main_size;

  bool line_has_in_flow_item = false;

  for (; next_item_index_ < all_items_.size(); ++next_item_index_) {
    const FlexItem& flex_item = all_items_[next_item_index_];
    DCHECK(!flex_item.ng_input_node_.IsOutOfFlowPositioned());

    LayoutUnit item_outer_hypothetical_main_size =
        flex_item.HypotheticalMainAxisMarginBoxSize();
    LayoutUnit gap_ contribution =
        line_has_in_flow_item ? gap_between_items_ : LayoutUnit();

    if (IsMultiline() &&
        sum_hypothetical_main_size + item_outer_hypothetical_main_size +
                gap_contribution >
            container_logical_width &&
        line_has_in_flow_item) {
      break;
    }

    line_items.push_back(flex_item);
    sum_flex_base_size += flex_item.FlexBaseMarginBoxSize() + gap_contribution;
    total_flex_grow += flex_item.flex_grow_;
    total_flex_shrink += flex_item.flex_shrink_;
    total_weighted_flex_shrink +=
        flex_item.flex_shrink_ * flex_item.flex_base_content_size_;
    sum_hypothetical_main_size +=
        item_outer_hypothetical_main_size + gap_contribution;
    line_has_in_flow_item = true;
  }
  // ... Construct and return FlexLine
}
```

### 2.2. Architectural Invariants in Blink

1. **Fixed-Point Arithmetic (`LayoutUnit`):** Blink represents coordinates and sizes using `LayoutUnit` (6-bit fractional fixed-point integers, $1/64\text{th}$ of a CSS pixel). In our formalization, we model `LayoutUnit` via exact integer arithmetic ($\mathbb{Z}$) where $1 \in \mathbb{Z}$ corresponds to `LayoutUnit::FromRawValue(1)`.
2. **Strict Termination & Progress (`line_has_in_flow_item`):** The boolean flag `line_has_in_flow_item` is structurally equivalent to `line_items.size() > 0` (`count > 0`). Because the `break` condition requires `line_has_in_flow_item == true`, the loop *must* execute its body for at least `next_item_index_` on entry, advancing `next_item_index_` by at least 1 per invocation of `ComputeNextFlexLine`.
3. **Line Capacity Bound:** For any generated `FlexLine` containing $n \ge 2$ items, the sum of outer hypothetical main sizes (plus $(n-1)$ inter-item gaps) is strictly bounded above by `container_logical_width` (`avail`). Only a singleton line ($n = 1$) may violate `sum_hypothetical <= avail`.
4. **Partition Completeness:** Across all calls to `ComputeNextFlexLine` until `next_item_index_ == all_items_.size()`, the concatenation of `line_items` across all returned `FlexLine` objects is identically equal to `all_items_`. Order and identity of items are strictly preserved.
5. **Cross-Axis Monotonicity:** In `FlexLayoutAlgorithm::AlignFlexLines`, when stretching lines (`align-content: stretch`) into available cross space `available_free_space > 0`, integer division distributes `available_free_space / num_lines` to each line, guaranteeing that line cross sizes never shrink and their sum increases by the distributed amount.

---

## 3. Formal Specification & Proofs in Rocq/Coq (`BlinkFlexboxMultilineWrapLineBreakingSemantics.v`)

Below is the complete, self-contained, and admitted-free Rocq/Coq formalization of Blink's multiline flexbox line breaking and cross-size distribution semantics.

```coq
(** * BlinkFlexboxMultilineWrapLineBreakingSemantics.v
    Formal Verification of W3C CSS Flexbox 1 §9.3 & §9.4
    Target: third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc
    Agent: 684 *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.Micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(* ========================================================================== *)
(* 1. DATA TYPES AND BASIC DEFINITIONS                                        *)
(* ========================================================================== *)

(** In Blink, LayoutUnit is a fixed-point number backed by a 32-bit integer.
    We model raw LayoutUnit ticks as exact integers Z. *)
Definition LayoutUnit := Z.

(** Representation of an in-flow FlexItem in Blink's FlexibleBoxAlgorithm. *)
Record FlexItem : Type := mkFlexItem {
  item_id : nat;
  flex_base_margin_box_size : LayoutUnit;
  hypothetical_main_axis_margin_box_size : LayoutUnit;
  hypothetical_cross_axis_margin_box_size : LayoutUnit;
  flex_grow : Z;
  flex_shrink : Z
}.

(** Well-formedness of a FlexItem: outer hypothetical cross sizes are non-negative,
    though margin boxes in main axis can theoretically be negative due to negative
    margins; we track general Z for main sizes and non-negative cross sizes. *)
Definition wf_flex_item (it : FlexItem) : Prop :=
  hypothetical_cross_axis_margin_box_size it >= 0.

(** Representation of a constructed FlexLine in Blink. *)
Record FlexLine : Type := mkFlexLine {
  line_items : list FlexItem;
  sum_hypothetical_main_size : LayoutUnit;
  sum_flex_base_size : LayoutUnit;
  cross_axis_extent : LayoutUnit
}.

(** Helper to compute the gap contribution before adding an item to a line.
    In Blink: `line_has_in_flow_item ? gap_between_items_ : LayoutUnit()` *)
Definition gap_contribution (count : nat) (gap : LayoutUnit) : LayoutUnit :=
  if Nat.eqb count 0 then 0 else gap.

(* ========================================================================== *)
(* 2. CORE MATHEMATICAL PROPERTY: LINE BREAKING PREDICATE                     *)
(* ========================================================================== *)

(** Mathematical Property Target:
    new_line_created(sum_hypothetical, avail) = (sum_hypothetical > avail && count > 0)
    Here `new_sum_hypothetical` represents the prospective running sum of the
    current line if the candidate item (and inter-item gap) were appended to it. *)
Definition new_line_created (new_sum_hypothetical avail : LayoutUnit) (count : nat) : bool :=
  (new_sum_hypothetical >? avail) && (negb (Nat.eqb count 0)).

(** Specification equivalence lemma for `new_line_created`. *)
Lemma new_line_created_spec :
  forall (new_sum avail : LayoutUnit) (count : nat),
    new_line_created new_sum avail count = true <->
    (new_sum > avail /\ (count > 0)%nat).
Proof.
  intros new_sum avail count.
  unfold new_line_created.
  rewrite andb_true_iff.
  rewrite Z.gtb_ltb, Z.ltb_lt.
  rewrite negb_true_iff, Nat.eqb_neq.
  split; intros [H1 H2]; split; lia.
Qed.

Lemma new_line_created_false_iff :
  forall (new_sum avail : LayoutUnit) (count : nat),
    new_line_created new_sum avail count = false <->
    (new_sum <= avail \/ count = 0%nat).
Proof.
  intros new_sum avail count.
  unfold new_line_created.
  rewrite andb_false_iff.
  rewrite Z.gtb_ltb, Z.ltb_ge.
  rewrite negb_false_iff, Nat.eqb_eq.
  split; intros [H | H]; [left | right | left | right]; lia.
Qed.

(** Crucial Progress Property: An empty line NEVER triggers a line break,
    even if the single item exceeds the available container width. *)
Theorem empty_line_never_breaks :
  forall (new_sum avail : LayoutUnit),
    new_line_created new_sum avail 0 = false.
Proof.
  intros new_sum avail.
  unfold new_line_created.
  simpl.
  rewrite andb_false_r.
  reflexivity.
Qed.

(* ========================================================================== *)
(* 3. BLINK LINE CONSTRUCTION ALGORITHM (ComputeNextFlexLine & All Lines)     *)
(* ========================================================================== *)

(** Calculates the exact hypothetical main size of a list of items with gaps. *)
Fixpoint calc_line_hypothetical_main (items : list FlexItem) (gap : LayoutUnit) : LayoutUnit :=
  match items with
  | [] => 0
  | [x] => hypothetical_main_axis_margin_box_size x
  | x :: xs => hypothetical_main_axis_margin_box_size x + gap + calc_line_hypothetical_main xs gap
  end.

(** Calculates the exact flex base size of a list of items with gaps. *)
Fixpoint calc_line_flex_base (items : list FlexItem) (gap : LayoutUnit) : LayoutUnit :=
  match items with
  | [] => 0
  | [x] => flex_base_margin_box_size x
  | x :: xs => flex_base_margin_box_size x + gap + calc_line_flex_base xs gap
  end.

(** Calculates initial cross size of a line as max of items' hypothetical cross sizes
    (CSS Flexbox §9.4 Step 8 without baseline alignment). *)
Fixpoint calc_line_cross_size (items : list FlexItem) : LayoutUnit :=
  match items with
  | [] => 0
  | x :: xs => Z.max (hypothetical_cross_axis_margin_box_size x) (calc