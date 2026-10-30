# Formal Verification Report: Table Caption Side Positioning (Top vs. Bottom Block Offset)

**Agent:** 698 (W3C/WHATWG Layout Rules — Grid, Tables, Shapes)  
**Topic:** Table Caption Side Positioning: Top vs. Bottom Block Offset  
**Chromium Source:** `third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc`  
**Specification:** CSS 2.1 §17.4 (`caption-side` top and bottom offsets)  
**Formal Theory Target:** `BlinkTableCaptionSideOffsetSemantics.v`  
**Core Mathematical Property:** $\text{table\_grid\_offset}(\text{caption\_side}, \text{caption\_h}) = \text{if } \text{is\_top} \text{ then } \text{caption\_h} \text{ else } 0$

---

## 1. Exact Normative W3C Specification Requirements

According to **CSS 2.1 §17.4 (Tables in the visual formatting model)**, a table element generates a principal block container box called the **table wrapper box** that contains the **table box** itself and any **caption boxes** (in document order). 

The normative formatting rules governing block-axis positioning of the table grid box and caption boxes are as follows:

1. **Table Wrapper Box Generation:** The table wrapper box establishes a block formatting context (or participates in one) and encloses both the table grid box and any associated `display: table-caption` children.
2. **The `caption-side` Property (§17.4.1):**
   * **Value `top`:** Positions the caption box(es) *above* the table box in the block progression direction.
   * **Value `bottom`:** Positions the caption box(es) *below* the table box in the block progression direction.
3. **Block-Axis Coordinate System Invariants:**
   * Let the block-start edge of the table wrapper box's content area be at coordinate $0$ (or base offset $B_{\text{start}}$).
   * All `top` captions are laid out sequentially starting from the block-start edge before the table grid box. If the cumulative block size (including margins) of `top` captions is $H_{\text{top}} \ge 0$, the table grid box is placed at block offset $H_{\text{top}}$.
   * If a single caption has block size `caption_h` and `caption-side` is `top`, then `table_grid_offset(Top, caption_h) = caption_h` and `caption_offset(Top, caption_h, grid_h) = 0`.
   * If `caption-side` is `bottom`, no `top` captions precede the table grid box. Thus, the table grid box is placed immediately at block offset $0$, and the bottom caption is placed immediately after the table grid box at block offset `grid_h`.
   * In both cases, the total intrinsic block size of the table wrapper content is invariant with respect to `caption-side`: $\text{TotalBlockSize} = \text{caption\_h} + \text{grid\_h}$.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink's LayoutNG architecture, table layout is governed by `TableLayoutAlgorithm` in `third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc`.

### 2.1 Key Data Structures and Execution Flow

During `TableLayoutAlgorithm::Layout()`, Blink separates table children into grouped structures (`TableGroupedChildren`) containing `captions` (a vector of `BlockNode`) and table parts (header, bodies, footer, columns).

```cpp
// Conceptual structure in third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc
struct CaptionResult {
  BlockNode node;
  const LayoutResult* layout_result;
  const BoxStrut margins;
};
```

Blink executes caption and grid layout in three phases:

1. **Caption Measurement (`ComputeCaptionFragments`):**
   Each caption node is laid out using the available inline size of the table wrapper. Its block size (`FragmentSize().block_size`) plus block margins (`margins.BlockSum()`) yields the effective block contribution `caption_h` of that caption.

2. **Top Captions Placement (Pre-Grid):**
   `TableLayoutAlgorithm` maintains a running block offset cursor `block_offset` (initialized to `BorderScrollbarPadding().block_start`). It iterates over all measured captions:
   ```cpp
   LayoutUnit block_offset = border_scrollbar_padding.block_start;
   for (const CaptionResult& caption : captions) {
     if (caption.node.Style().CaptionSide() == ECaptionSide::kTop) {
       block_offset += caption.margins.block_start;
       container_builder_.AddResult(*caption.layout_result,
                                    LogicalOffset(inline_offset, block_offset));
       block_offset += NGFragment(writing_direction, caption.layout_result->PhysicalFragment()).BlockSize() 
                       + caption.margins.block_end;
     }
   }
   ```

3. **Table Grid Box & Bottom Captions Placement:**
   Once all `ECaptionSide::kTop` captions are added, `block_offset` represents the exact block-start coordinate of the table grid box (`table_grid_block_offset`):
   ```cpp
   const LayoutUnit grid_block_offset = block_offset;
   // Table grid sections (thead, tbody, tfoot) and borders/paddings are laid out starting at grid_block_offset.
   block_offset += grid_block_size;

   for (const CaptionResult& caption : captions) {
     if (caption.node.Style().CaptionSide() == ECaptionSide::kBottom) {
       block_offset += caption.margins.block_start;
       container_builder_.AddResult(*caption.layout_result,
                                    LogicalOffset(inline_offset, block_offset));
       block_offset += NGFragment(writing_direction, caption.layout_result->PhysicalFragment()).BlockSize() 
                       + caption.margins.block_end;
     }
   }
   ```

### 2.2 Core Implementation Invariants

1. **Zero-Base Top Offset Invariant:** Relative to `border_scrollbar_padding.block_start`, if there is a single caption of total outer block size `caption_h`, the grid block offset is `caption_h` when `CaptionSide() == ECaptionSide::kTop` and `0` when `CaptionSide() == ECaptionSide::kBottom`.
2. **Non-Overlapping Disjointness Invariant:** For non-negative `caption_h` and `grid_h`, the half-open intervals occupied by the caption box and the table grid box along the block axis are strictly disjoint (or empty if size is 0) and contiguous.
3. **Wrapper Block-Size Commutativity Invariant:** Toggling `caption-side` between `top` and `bottom` permutes the vertical ordering of the caption and grid fragments without altering the final `block_offset` accumulated at the end of `TableLayoutAlgorithm::Layout()`.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkTableCaptionSideOffsetSemantics.v`. It models both the single-caption core mathematical property and the generalized multi-caption accumulation algorithm in `table_layout_algorithm.cc`.

```coq
(** * BlinkTableCaptionSideOffsetSemantics.v
    Formal Verification of W3C CSS 2.1 §17.4 Table Caption Side Positioning
    in Chromium Blink (table_layout_algorithm.cc). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Basic Types and CSS Property Definitions *)

(** Representation of CSS 2.1 §17.4.1 `caption-side` property (`ECaptionSide` in Blink). *)
Inductive CaptionSide : Type :=
  | CaptionTop : CaptionSide
  | CaptionBottom : CaptionSide.

(** Boolean decidability and predicate for `caption-side: top`. *)
Definition is_top (side : CaptionSide) : bool :=
  match side with
  | CaptionTop => true
  | CaptionBottom => false
  end.

Definition is_bottom (side : CaptionSide) : bool :=
  negb (is_top side).

(** Block-axis margin strut for a caption box (`BoxStrut` in Blink). *)
Record BlockMargins : Type := mkBlockMargins {
  margin_block_start : Z;
  margin_block_end : Z
}.

(** A laid-out caption fragment (`CaptionResult` in `table_layout_algorithm.cc`). *)
Record CaptionFragment : Type := mkCaptionFragment {
  caption_side : CaptionSide;
  caption_block_size : Z;
  caption_margins : BlockMargins
}.

(** Outer block contribution of a single caption (fragment block size + block margins). *)
Definition caption_outer_block_size (c : CaptionFragment) : Z :=
  margin_block_start (caption_margins c) +
  caption_block_size c +
  margin_block_end (caption_margins c).

(** ** 2. Core Single-Caption Offset Semantics *)

(** Core mathematical property:
    table_grid_offset(caption_side, caption_h) = if is_top then caption_h else 0. *)
Definition table_grid_offset (side : CaptionSide) (caption_h : Z) : Z :=
  if is_top side then caption_h else 0.

(** Block offset of the caption box itself (outer border-box + margin start base)
    relative to the table wrapper content block-start edge. *)
Definition caption_block_offset (side : CaptionSide) (caption_h grid_h : Z) : Z :=
  if is_top side then 0 else grid_h.

(** Total block size of the table wrapper content box for a single caption and grid. *)
Definition wrapper_total_block_size (side : CaptionSide) (caption_h grid_h : Z) : Z :=
  if is_top side
  then table_grid_offset side caption_h + grid_h
  else caption_block_offset side caption_h grid_h + caption_h.

(** ** 3. Multi-Caption Blink Algorithm Model (`table_layout_algorithm.cc`) *)

(** Accumulates block offsets for captions matching `target_side` starting at `init_offset`. *)
Fixpoint accumulate_captions_by_side
  (target_top : bool)
  (captions : list CaptionFragment)
  (current_offset : Z) : Z :=
  match captions with
  | [] => current_offset
  | c :: rest =>
      if Bool.eqb (is_top (caption_side c)) target_top
      then accumulate_captions_by_side target_top rest (current_offset + caption_outer_block_size c)
      else accumulate_captions_by_side target_top rest current_offset
  end.

(** Blink's `TableLayoutAlgorithm::Layout` block offset computation:
    1. Start at `bsp_block_start` (border_scrollbar_padding.block_start).
    2. Accumulate all `kTop` captions -> yields `grid_block_offset`.
    3. Add `grid_block_size`.
    4. Accumulate all `kBottom` captions -> yields `final_block_offset`. *)
Definition blink_table_grid_block_offset
  (bsp_block_start : Z)
  (captions : list CaptionFragment) : Z :=
  accumulate_captions_by_side true captions bsp_block_start.

Definition blink_table_final_block_offset
  (bsp_block_start : Z)
  (captions : list CaptionFragment)
  (grid_block_size : Z) : Z :=
  let grid_offset := blink_table_grid_block_offset bsp_block_start captions in
  accumulate_captions_by_side false captions (grid_offset + grid_block_size).

(** Sum of outer block sizes of all captions in a list regardless of side. *)
Fixpoint sum_all_captions (captions : list CaptionFragment) : Z :=
  match captions with
  | [] => 0
  | c :: rest => caption_outer_block_size c + sum_all_captions rest
  end.

(** ** 4. Geometric Interval Predicates for Box Disjointness *)

(** Two half-open block intervals [s1, e1) and [s2, e2) are non-overlapping. *)
Definition intervals_disjoint (s1 e1 s2 e2 : Z) : Prop :=
  e1 <= s2 \/ e2 <= s1.

(** Two intervals [s1, e1) and [s2, e2) partition [0, total) contiguously. *)
Definition intervals_partition (s1 e1 s2 e2 total : Z) : Prop :=
  (s1 = 0 /\ e1 = s2 /\ e2 = total) \/
  (s2 = 0 /\ e2 = s1 /\ e1 = total).
```

---

## 4. Concrete Theorems and Complete Proofs

All theorems below are proven without `admit` or `Admitted`, using standard `ZArith`, `Lia`, `Bool`, and `List` tactics.

```coq
(** * Formal Proofs of Blink Table Caption Positioning Invariants *)

(** ** Theorem 1: Exact Characterization of `table_grid_offset` *)
Theorem table_grid_offset_spec :
  forall (side : CaptionSide) (caption_h : Z),
    table_grid_offset side caption_h = (if is_top side then caption_h else 0) /\
    (side = CaptionTop -> table_grid_offset side caption_h = caption_h) /\
    (side = CaptionBottom -> table_grid_offset side caption_h = 0).
Proof.
  intros side caption_h.
  unfold table_grid_offset.
   repeat split; intros H; subst; simpl; reflexivity.
Qed.

(** ** Theorem 2: Non-Negativity Preservation of Grid Block Offset *)
Theorem table_grid_offset_nonneg :
  forall (side : CaptionSide) (caption_h : Z),
    0 <= caption_h ->
    0 <= table_grid_offset side caption_h <= caption_h.
Proof.
  intros side caption_h Hnonneg.
  unfold table_grid_offset.
  destruct side; simpl; lia.
Qed.

(** ** Theorem 3: Wrapper Total Block Size Invariance under `caption-side` *)
Theorem wrapper_total_block_size_invariant :
  forall (side : CaptionSide) (caption_h grid_h : Z),
    wrapper_total_block_size side caption_h grid_h = caption_h + grid_h.
Proof.
  intros side caption_h grid_h.
  unfold wrapper_total_block_size, table_grid_offset, caption_block_offset.
  destruct side; simpl; lia.
Qed.

(** ** Theorem 4: Disjoint Contiguous Partitioning of Caption and Grid Boxes *)
Theorem caption_and_grid