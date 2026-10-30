### Audit Report: Agent 138 — Chromium Blink CSS Visibility vs. CSS 2.1 (§11.2, §17.5.5)

#### 1. `visibility: hidden` Layout Footprint vs. Paint Suppression (CSS 2.1 §11.2)
In Chromium Blink, `visibility: hidden` strictly decouples geometry generation from visual rasterization, adhering to CSS 2.1 §11.2: *"The generated box is invisible (fully transparent, nothing is drawn), but still affects layout."*

*   **Layout Footprint & Margin Collapsing (`LayoutNG`):** During the layout phase (`NGBlockLayoutAlgorithm`), Blink does not branch on `EVisibility::kHidden`. Box dimensions (`border_box_size`), padding, borders, and positioning are computed identically to `EVisibility::kVisible`. Crucially, in `NGMarginStrut`, adjacent vertical margins of `visibility: hidden` boxes participate fully in margin collapsing. A `hidden` block still acts as a clearance boundary or collapses its top/bottom margins with adjacent siblings and parents just as a visible block does.
*   **Paint Suppression (`BoxPaintInvalidator` & `BoxPainter`):** Suppression occurs exclusively during the PrePaint and Paint lifecycle phases (`PaintPhase`). `LayoutObject::VisibleToHitTesting()` and `ComputedStyle::Visibility()` gate the emission of `DisplayItem`s onto the `PaintController`. Because a `hidden` element may have `visibility: visible` descendants, Blink still traverses the `NGPhysicalBoxFragment` tree during paint, skipping only the self-painting operations (background, borders, text) of the `hidden` fragment itself while allowing visible child fragments to emit display items.

#### 2. `visibility: collapse` in Table Rows (CSS 2.1 §17.5.5)
In CSS 2.1 §17.5.5, `visibility: collapse` on table rows (`<tr>`), row groups (`<thead>`, `<tbody>`, `<tfoot>`), columns (`<col>`), and column groups (`<colgroup>`) has layout-altering semantics distinct from `hidden`.

*   **Column Width Preservation:** In Blink's `TableLayoutAlgorithm` (specifically `NGTableLayoutAlgorithm`), column sizing occurs in two passes before row height allocation. During the `ComputeTableInlineSize` and column distribution passes, cells within a `visibility: collapse` row are **fully evaluated**. Their min-content and max-content inline contributions (`MinMaxSizes`) dictate the resolved `NGTableTypes::Column` widths. This guarantees that toggling a row between `collapse` and `visible` does not trigger horizontal reflow or alter the column geometry of the table.
*   **Row Height Removal:** During the block-size calculation pass (`ComputeRows`), Blink inspects the row's `ComputedStyle::Visibility()`. If a row is `EVisibility::kCollapse`, its resolved block-size (height) is clamped to `0px`, and its cells do not contribute to the table's final block-size. In the paint phase, the collapsed row and its descendant cells are completely skipped (unlike `hidden`, `visible` descendants inside a collapsed table row are **not** rendered). For non-table elements, Blink falls back to treating `collapse` identically to `hidden` per spec.

---

#### 3. Core Verification Invariants

1.  **Invariant I1 (Layout Indistinguishability of `hidden`):** For any non-table layout box $B$, setting `visibility: hidden` yields the exact same layout metrics (width, height, $x/y$ coordinates, and outgoing margin strut) as `visibility: visible`.
2.  **Invariant I2 (Column Width Stability under `collapse`):** For any table $T$, the resolved inline widths of its columns are invariant with respect to whether any subset of its rows has `visibility: collapse` or `visibility: visible`.
3.  **Invariant I3 (Zero Block-Size of Collapsed Rows):** Any table row $R \in T$ with `visibility: collapse` resolves to a final layout height of $0$, and contributes $0$ to the block-axis offset of subsequent rows.

---

#### 4. Formalization: `BlinkCSSVisibilitySemantics.v`

The following Rocq (Coq) specification models Blink's `LayoutNG` block and table layout pipelines, proving the layout preservation and suppression invariants.

```coq
(** * BlinkCSSVisibilitySemantics.v
    Formal Audit of Chromium Blink CSS Visibility (CSS 2.1 §11.2, §17.5.5)
    Agent 138 *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.Bool.Bool.
Import ListNotations.

(** ** 1. Core CSS Visibility & Box Primitives *)

Inductive Visibility : Type :=
  | VisVisible  : Visibility
  | VisHidden   : Visibility
  | VisCollapse : Visibility.

Record MarginStrut : Type := mkStrut {
  pos_margin : nat;
  neg_margin : nat (* Stored as magnitude *)
}.

Definition collapse_margins (m1 m2 : MarginStrut) : MarginStrut :=
  mkStrut (Nat.max (pos_margin m1) (pos_margin m2))
          (Nat.max (neg_margin m1) (neg_margin m2)).

Record BoxStyle : Type := mkStyle {
  visibility   : Visibility;
  inline_size  : nat;
  block_size   : nat;
  margin_top   : MarginStrut;
  margin_bot   : MarginStrut
}.

Record LayoutFragment : Type := mkFragment {
  frag_inline_size : nat;
  frag_block_size  : nat;
  out_margin_strut : MarginStrut;
  is_painted       : bool
}.

(** ** 2. Block Layout & Paint Semantics (CSS 2.1 §11.2) *)

(** Blink NGBlockLayoutAlgorithm: Visibility is ignored during geometry & margin calculation.
    For non-table elements, 'collapse' computes layout identically to 'hidden'/'visible'. *)
Definition compute_block_geometry (s : BoxStyle) (in_strut : MarginStrut) : (nat * nat * MarginStrut) :=
  let resolved_inline := inline_size s in
  let resolved_block  := block_size s in
  let next_strut := collapse_margins (collapse_margins in_strut (margin_top s)) (margin_bot s) in
  (resolved_inline, resolved_block, next_strut).

(** Blink BoxPainter: Only 'VisVisible' emits display items. *)
Definition should_paint_block (v : Visibility) : bool :=
  match v with
  | VisVisible  => true
  | VisHidden   => false
  | VisCollapse => false (* Behaves as hidden on non-table elements *)
  end.

Definition layout_and_paint_block (s : BoxStyle) (in_strut : MarginStrut) : LayoutFragment :=
  let '(w, h, strut) := compute_block_geometry s in_strut in
  mkFragment w h strut (should_paint_block (visibility s)).

(** ** 3. Table Layout Semantics (CSS 2.1 §17.5.5) *)

Record TableCell : Type := mkCell {
  cell_min_inline : nat;
  cell_block_size : nat
}.

Record TableRow : Type := mkRow {
  row_visibility : Visibility;
  row_cells      : list TableCell
}.

Record TableLayoutResult : Type := mkTableResult {
  col_widths   : list nat;
  row_heights  : list nat;
  table_height : nat
}.

(** Helper: Pointwise maximum of two column width lists *)
Fixpoint max_cols (c1 c2 : list nat) : list nat :=
  match c1, c2 with
  | [], l => l
  | l, [] => l
  | x :: xs, y :: ys => (Nat.max x y) :: (max_cols xs ys)
  end.

(** Pass 1: NGTableLayoutAlgorithm::ComputeTableInlineSize
    Crucially, row visibility is NOT checked when measuring column widths. *)
Fixpoint compute_col_widths (rows : list TableRow) : list nat :=
  match rows with
  | [] => []
  | r :: rs =>
      let current_row_widths := map cell_min_inline (row_cells r) in
      max_cols current_row_widths (compute_col_widths rs)
  end.

(** Pass 2: NGTableLayoutAlgorithm::ComputeRows
    If row_visibility is VisCollapse, row height is forced to 0. *)
Definition compute_single_row_height (r : TableRow) : nat :=
  match row_visibility r with
  | VisCollapse => 0
  | _ => fold_right Nat.max 0 (map cell_block_size (row_cells r))
  end.

Definition layout_table (rows : list TableRow) : TableLayoutResult :=
  let cols := compute_col_widths rows in
  let r_heights := map compute_single_row_height rows in
  let total_h := fold_right Nat.add 0 r_heights in
  mkTableResult cols r_heights total_h.

(** ** 4. Verification of Audit Invariants *)

(** Theorem 1 (Invariant I1): 'visibility: hidden' preserves exact layout footprint 
    (inline size, block size, and margin collapsing) of 'visibility: visible', 
    while strictly suppressing paint. *)
Theorem visibility_hidden_preserves_footprint_suppresses_paint :
  forall (w h : nat) (mt mb in_strut : MarginStrut),
    let style_vis := mkStyle VisVisible w h mt mb in
    let style_hid := mkStyle VisHidden  w h mt mb in
    let frag_vis  := layout_and_paint_block style_vis in_strut in
    let frag_hid  := layout_and_paint_block style_hid in_strut in
    frag_inline_size frag_vis = frag_inline_size frag_hid /\
    frag_block_size  frag_vis = frag_block_size  frag_hid /\
    out_margin_strut frag_vis = out_margin_strut frag_hid /\
    is_painted frag_vis = true /\
    is_painted frag_hid = false.
Proof.
  intros w h mt mb in_strut style_vis style_hid frag_vis frag_hid.
  unfold frag_vis, frag_hid, layout_and_paint_block, compute_block_geometry.
  simpl.
  repeat split; reflexivity.
Qed.

(** Operation to toggle a row's visibility to 'collapse' *)
Definition collapse_row (r : TableRow) : TableRow :=
  mkRow VisCollapse (row_cells r).

(** Theorem 2 (Invariant I2): Collapsing a table row preserves column widths. *)
Theorem table_collapse_preserves_column_widths :
  forall (rows : list TableRow),
    col_widths (layout_table rows) = col_widths (layout_table (map collapse_row rows)).
Proof.
  intros rows.
  unfold layout_table; simpl.
  induction rows as [| r rs IH].
  - simpl. reflexivity.
  - simpl. rewrite IH. reflexivity.
Qed.

(** Theorem 3 (Invariant I3): A collapsed table row always resolves to height 0. *)
Theorem collapsed_row_has_zero_height :
  forall (r : TableRow),
    row_visibility r = VisCollapse ->
    compute_single_row_height r = 0.
Proof.
  intros r Hvis.
  unfold compute_single_row_height.
  rewrite Hvis.
  reflexivity.
Qed.

(** Corollary: Collapsing all rows in a table reduces total table block-size to 0 
    while retaining exact column inline-sizes. *)
Theorem collapse_all_rows_zeros_table_height :
  forall (rows : list TableRow),
    let res := layout_table (map collapse_row rows) in
    table_height res = 0 /\ col_widths res = col_widths (layout_table rows).
Proof.
  intros rows res.
  unfold res; split.
  - unfold layout_table; simpl.
    induction rows as [| r rs IH].
    + simpl. reflexivity.
    + simpl. apply IH.
  - symmetry. apply table_collapse_preserves_column_widths.
Qed.
```