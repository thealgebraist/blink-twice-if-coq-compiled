### Agent 128 Audit Report: Chromium Blink Table Caption Placement vs. CSS 2.1 §17.4

In Chromium Blink’s LayoutNG architecture (`NGTableLayoutAlgorithm`), a `<table>` element generates a primary wrapper box (the *table wrapper box* in CSS 2.1 §17.4) that establishes a block formatting context containing the table grid box itself and any associated `<caption>` boxes.

---

### 1. Caption Positioning (`caption-side: top | bottom`)

Per CSS 2.1 §17.4, `caption-side` dictates the vertical placement of the caption block relative to the table grid box inside the anonymous table wrapper box:
* **`caption-side: top`**: Blink iterates through top captions first in `NGTableLayoutAlgorithm::Layout()`, computing their block-size and margins, advancing the current `block_offset` cursor before placing the table grid box. The caption is placed at $Y_{\text{caption}} = 0$ (plus top margins), and the table grid begins at $Y_{\text{grid}} \ge Y_{\text{caption}} + H_{\text{caption}}$.
* **`caption-side: bottom`**: After laying out the table grid box and advancing the `block_offset` by the grid's block-size, Blink iterates through bottom captions, positioning them at $Y_{\text{caption}} \ge Y_{\text{grid}} + H_{\text{grid}}$.

---

### 2. Caption Width Alignment

Per CSS 2.1 §17.4 and CSS Tables Module Level 3, the horizontal margins of the caption box are formatted within an available inline-size equal to the final inline-size of the table grid box:
* Blink first computes the used inline-size of the table grid ($W_{\text{grid}}$) based on table-layout algorithms (`fixed` or `auto`), border-spacing, and column constraints.
* Blink then constructs an `NGConstraintSpace` for each caption child where the available inline-size is fixed to $W_{\text{grid}}$. Assuming zero horizontal margins and `width: auto`, the caption's border-box width matches the table grid box width: $W_{\text{caption}} = W_{\text{grid}}$.

---

### 3. Layout Invariants

Assuming collapsed/zero vertical margins for structural box verification:
1. **Top Caption Ordering Invariant**:
   $$\text{caption\_side} = \text{Top} \implies Y_{\text{caption}} + H_{\text{caption}} \le Y_{\text{grid}}$$
2. **Bottom Caption Ordering Invariant**:
   $$\text{caption\_side} = \text{Bottom} \implies Y_{\text{grid}} + H_{\text{grid}} \le Y_{\text{caption}}$$
3. **Inline-Size Equivalence Invariant**:
   $$W_{\text{caption}} = W_{\text{grid}} \land W_{\text{wrapper}} = W_{\text{grid}}$$
4. **Block-Size Conservation Invariant**:
   $$H_{\text{table\_total}} = H_{\text{caption}} + H_{\text{grid}}$$

---

### 4. Formal Verification: `BlinkTableCaptionLayoutSemantics.v`

The following Coq (Rocq) module formalizes Blink's `NGTableLayoutAlgorithm` geometry for single-caption table structures and verifies compliance with CSS 2.1 §17.4 invariants.

```coq
(** * BlinkTableCaptionLayoutSemantics.v
    Formalization of Chromium Blink LayoutNG Table Caption Placement
    vs. CSS 2.1 Section 17.4 (Tables in the visual formatting model).
    Agent 128 Audit Artifact. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Set Implicit Arguments.

(** ** 1. Data Types & CSS Property Definitions *)

Inductive CaptionSide : Type :=
  | CaptionTop : CaptionSide
  | CaptionBottom : CaptionSide.

(** Input dimensions prior to block placement *)
Record BoxDimensions : Type := mkDimensions {
  dim_width  : nat;
  dim_height : nat
}.

(** Computed physical layout rectangle relative to the Table Wrapper Box *)
Record LayoutRect : Type := mkRect {
  rect_x      : nat;
  rect_y      : nat;
  rect_width  : nat;
  rect_height : nat
}.

(** Input specification for a Table with a Caption *)
Record TableLayoutInput : Type := mkTableInput {
  in_caption_side   : CaptionSide;
  in_grid_dims      : BoxDimensions;
  in_caption_height : nat
}.

(** Output of Blink's NGTableLayoutAlgorithm *)
Record TableWrapperLayout : Type := mkWrapperLayout {
  out_wrapper_width  : nat;
  out_wrapper_height : nat;
  out_grid_rect      : LayoutRect;
  out_caption_rect   : LayoutRect
}.

(** ** 2. Blink NGTableLayoutAlgorithm Semantics *)

(** Computes the layout of the table wrapper, grid, and caption boxes.
    Models Chromium's NGTableLayoutAlgorithm::Layout() where caption constraint
    spaces receive the resolved table grid inline-size. *)
Definition layout_table_with_caption (inp : TableLayoutInput) : TableWrapperLayout :=
  let grid_w := dim_width (in_grid_dims inp) in
  let grid_h := dim_height (in_grid_dims inp) in
  let cap_h  := in_caption_height inp in
  match in_caption_side inp with
  | CaptionTop =>
      mkWrapperLayout
        grid_w
        (cap_h + grid_h)
        (mkRect 0 cap_h grid_w grid_h) (* Grid placed below top caption *)
        (mkRect 0 0     grid_w cap_h)  (* Caption placed at origin *)
  | CaptionBottom =>
      mkWrapperLayout
        grid_w
        (grid_h + cap_h)
        (mkRect 0 0      grid_w grid_h) (* Grid placed at origin *)
        (mkRect 0 grid_h grid_w cap_h)  (* Caption placed below grid *)
  end.

(** ** 3. CSS 2.1 §17.4 Invariant Proofs *)

(** Theorem 1: Caption width matches table grid width and wrapper width. *)
Theorem caption_width_matches_grid :
  forall (inp : TableLayoutInput),
    let res := layout_table_with_caption inp in
    rect_width (out_caption_rect res) = rect_width (out_grid_rect res) /\
    out_wrapper_width res = rect_width (out_grid_rect res).
Proof.
  intros inp res.
  unfold res, layout_table_with_caption.
  destruct (in_caption_side inp); simpl; split; reflexivity.
Qed.

(** Theorem 2: Top caption placement invariant (Y_cap + H_cap <= Y_grid). *)
Theorem top_caption_above_grid_invariant :
  forall (inp : TableLayoutInput),
    in_caption_side inp = CaptionTop ->
    let res := layout_table_with_caption inp in
    let cap := out_caption_rect res in
    let grid := out_grid_rect res in
    rect_y cap + rect_height cap <= rect_y grid.
Proof.
  intros inp Hside res cap grid.
  unfold cap, grid, res, layout_table_with_caption.
  rewrite Hside. simpl.
  lia.
Qed.

(** Theorem 3: Bottom caption placement invariant (Y_grid + H_grid <= Y_cap). *)
Theorem bottom_caption_below_grid_invariant :
  forall (inp : TableLayoutInput),
    in_caption_side inp = CaptionBottom ->
    let res := layout_table_with_caption inp in
    let cap := out_caption_rect res in
    let grid := out_grid_rect res in
    rect_y grid + rect_height grid <= rect_y cap.
Proof.
  intros inp Hside res cap grid.
  unfold cap, grid, res, layout_table_with_caption.
  rewrite Hside. simpl.
  lia.
Qed.

(** Theorem 4: Table total height equals caption_height + grid_height. *)
Theorem table_total_height_conservation :
  forall (inp : TableLayoutInput),
    let res := layout_table_with_caption inp in
    out_wrapper_height res =
      rect_height (out_caption_rect res) + rect_height (out_grid_rect res).
Proof.
  intros inp res.
  unfold res, layout_table_with_caption.
  destruct (in_caption_side inp); simpl; lia.
Qed.

(** Theorem 5: Geometric Non-Overlap and Bounding Box Completeness.
    Verifies that neither box exceeds the wrapper height and their vertical
    projections are strictly disjoint. *)
Theorem table_boxes_bounded_and_disjoint :
  forall (inp : TableLayoutInput),
    let res := layout_table_with_caption inp in
    let cap := out_caption_rect res in
    let grid := out_grid_rect res in
    (rect_y cap + rect_height cap <= out_wrapper_height res) /\
    (rect_y grid + rect_height grid <= out_wrapper_height res) /\
    (rect_y cap + rect_height cap <= rect_y grid \/
     rect_y grid + rect_height grid <= rect_y cap).
Proof.
  intros inp res cap grid.
  unfold cap, grid, res, layout_table_with_caption.
  destruct (in_caption_side inp); simpl; repeat split; lia.
Qed.
```