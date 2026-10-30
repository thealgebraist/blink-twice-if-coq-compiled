Here is the formal audit and semantic model for Chromium Blink’s Nested Table Layout against CSS 2.1 §17.5.

---

### 1. Inline-Size Propagation: Outer Cell to Inner Table

When a `LayoutNGTable` (or `TableLayoutAlgorithm` in Blink's LayoutNG architecture) is embedded inside a `LayoutNGTableCell` (`<td>` or `<th>`), the outer table's layout passes through two primary horizontal phases before establishing the inner table's geometry:

1. **Intrinsic Sizes Pass (`ComputeMinMaxSizes`):**
   - The outer table queries each cell for its `MinMaxSizes` (minimum content size and maximum content size).
   - The outer cell delegates this to its children via `BlockLayoutAlgorithm`. When it encounters the inner table, `TableLayoutAlgorithm::ComputeMinMaxSizes` is invoked on the inner table.
   - The inner table aggregates the min/max sizes of its own columns, borders, and cell spacings, returning them to the outer cell. The outer cell adds its own inline padding and border to establish its intrinsic inline contribution to the outer table's column-sizing algorithm (`TableTypes::Column`).

2. **Layout Pass (`Layout`):**
   - Once the outer table resolves its column widths (via fixed or auto table layout algorithms per CSS 2.1 §17.5.2), it assigns a definitive inline size to the outer cell.
   - The outer cell constructs a `ConstraintSpace` for its block formatting context. The **available inline size** of this constraint space is computed as:
     $$\text{AvailableInlineSize}_{\text{cell}} = \text{InlineSize}_{\text{cell}} - (\text{BorderInline}_{\text{cell}} + \text{PaddingInline}_{\text{cell}})$$
   - This `AvailableInlineSize` serves directly as the **containing block width** for the inner table.
   - The inner table resolves its own width against this containing block width:
     - If `width: auto` (shrink-to-fit), its used inline size is:
       $$\min(\max(\text{min\_content}, \text{AvailableInlineSize}_{\text{cell}}), \text{max\_content})$$
       (clamped and adjusted by the inner table's inline margins).
     - If `width` is a percentage or fixed length, it resolves against $\text{AvailableInlineSize}_{\text{cell}}$, while still respecting the inner table's `min_content` floor (since tables cannot shrink below their minimum intrinsic content width in CSS 2.1).

---

### 2. Block-Size Contribution: Inner Table to Outer Cell and Row

In CSS 2.1 §17.5.3, table height is dictated by the content of the cells and explicit height properties. In Blink's `TableLayoutAlgorithm`, vertical sizing for nested tables proceeds as follows:

1. **Unconstrained Block Layout of the Cell:**
   - During the outer table's row-sizing phase, the outer cell is initially laid out with an **indefinite** (`kIndefiniteSize`) available block size in its `ConstraintSpace` (unless percentage resolution requires a pass with a fixed row height).
   - The inner table executes its complete layout cycle: computing its column widths, laying out its own rows, and summing row heights, border-spacings, borders, and captions to produce an intrinsic block size $\text{Height}_{\text{inner\_table}}$.
   - The inner table returns a `PhysicalBoxFragment` with this block size to the outer cell's `BlockLayoutAlgorithm`.

2. **Outer Cell Block Size Aggregation:**
   - The outer cell accumulates the block sizes of all inflow children (including the inner table's margin box: $\text{MarginBlock}_{\text{inner}} + \text{Height}_{\text{inner\_table}}$) plus its own block-axis border and padding:
     $$\text{ContentBlockSize}_{\text{cell}} = \text{BorderBlock}_{\text{cell}} + \text{PaddingBlock}_{\text{cell}} + \sum \text{ChildMarginBoxBlockSize}$$
   - The cell's minimum contribution to its row is $\max(\text{SpecifiedBlockSize}_{\text{cell}}, \text{ContentBlockSize}_{\text{cell}})$.

3. **Outer Row Height Resolution and Alignment Pass:**
   - The outer row height $\text{Height}_{\text{row}}$ is calculated as the maximum block size required by any non-spanning cell in that row (along with distributed heights from `rowspan` cells and the row's own specified `height`).
   - Once $\text{Height}_{\text{row}}$ is finalized, Blink performs a final layout/alignment pass on the outer cells using a `ConstraintSpace` with a **fixed block size** equal to $\text{Height}_{\text{row}}$.
   - If $\text{Height}_{\text{row}} > \text{ContentBlockSize}_{\text{cell}}$, the extra block space is converted into synthesized intrinsic padding (to implement `vertical-align: middle | bottom | baseline`). The inner table's fragment is shifted downward within the outer cell's coordinate space accordingly, without altering the inner table's height (unless the inner table has a percentage height that resolves against the cell).

---

### 3. Core Geometric Invariants

Under standard flow (in-flow nested table, non-negative margins, no overflow clipping overrides):

1. **Block-Axis Containment & Monotonicity:**
   $$\text{Height}_{\text{outer\_row}} = \text{Height}_{\text{outer\_cell}} \ge \text{BorderPaddingBlock}_{\text{outer\_cell}} + \text{MarginBlock}_{\text{inner\_table}} + \text{Height}_{\text{inner\_table}}$$
   Specifically, ignoring borders/paddings/margins: $\text{Height}_{\text{outer\_cell}} \ge \text{Height}_{\text{inner\_table}}$.

2. **Bounding Box Containment (Vertical):**
   Let $y_{\text{inner}}$ be the block offset of the inner table relative to the outer cell. Because `vertical-align` distributes non-negative residual space $\Delta = \text{Height}_{\text{outer\_cell}} - \text{ContentBlockSize}_{\text{cell}} \ge 0$:
   $$0 \le \text{BorderTop}_{\text{cell}} + \text{PaddingTop}_{\text{cell}} + \text{MarginTop}_{\text{inner}} \le y_{\text{inner}}$$
   $$y_{\text{inner}} + \text{Height}_{\text{inner\_table}} \le \text{Height}_{\text{outer\_cell}} - (\text{BorderBottom}_{\text{cell}} + \text{PaddingBottom}_{\text{cell}} + \text{MarginBottom}_{\text{inner}}) \le \text{Height}_{\text{outer\_cell}}$$

3. **Bounding Box Containment (Horizontal):**
   Assuming the outer table's column sizing algorithm properly propagates the inner table's `min_content` inline size to the outer cell's minimum width, we have $\text{AvailableInlineSize}_{\text{cell}} \ge \text{min\_content}_{\text{inner\_table}}$. Consequently, the resolved inner table width satisfies:
   $$\text{Width}_{\text{inner\_table}} + \text{MarginInline}_{\text{inner}} \le \text{AvailableInlineSize}_{\text{cell}}$$
   $$0 \le x_{\text{inner}} \quad \land \quad x_{\text{inner}} + \text{Width}_{\text{inner\_table}} \le \text{Width}_{\text{outer\_cell}}$$

---

### 4. Formal Verification in Rocq/Coq (`BlinkNestedTableLayoutSemantics.v`)

Below is a complete, self-contained Rocq (Coq) formalization modeling the nested table layout pass, intrinsic size propagation, vertical alignment, and proofs of the containment invariants.

```coq
(** * BlinkNestedTableLayoutSemantics.v
    Formal audit of Chromium Blink Nested Table Layout vs CSS 2.1 §17.5 *)

From Coq Require Import Arith PeanoNat Lia List.
Import ListNotations.

(** ** 1. Basic Data Structures & Edges *)

Record BoxEdges := mkEdges {
  top    : nat;
  bottom : nat;
  left   : nat;
  right  : nat
}.

Definition inline_sum (e : BoxEdges) : nat := left e + right e.
Definition block_sum  (e : BoxEdges) : nat := top e + bottom e.

Record MinMaxSizes := mkMinMax {
  min_size : nat;
  max_size : nat;
  minmax_wf : min_size <= max_size
}.

Inductive VerticalAlign :=
  | VTop
  | VMiddle
  | VBottom.

Inductive StyleWidth :=
  | WAuto
  | WFixed (w : nat).

(** ** 2. Inner Table Model *)

Record InnerTableStyle := mkInnerTable {
  it_width_style : StyleWidth;
  it_minmax      : MinMaxSizes;
  it_margins     : BoxEdges;
  it_border_pad  : BoxEdges;
  it_rows_height : list nat; (* Intrinsic heights of inner rows *)
}.

(** Compute the intrinsic block size of the inner table *)
Definition compute_inner_table_height (it : InnerTableStyle) : nat :=
  block_sum (it_border_pad it) + fold_right Nat.add 0 (it_rows_height it).

(** CSS 2.1 §17.5.2 & Blink TableLayoutAlgorithm width resolution:
    An inner table's width is clamped below by its min_size, and if Auto,
    shrinks-to-fit the available inline size of the containing block. *)
Definition resolve_inner_table_width (it : InnerTableStyle) (cb_avail_width : nat) : nat :=
  let avail_after_margins := cb_avail_width - inline_sum (it_margins it) in
  let mm := it_minmax it in
  match it_width_style it with
  | WAuto =>
      Nat.max (min_size mm) (Nat.min avail_after_margins (max_size mm))
  | WFixed w =>
      Nat.max (min_size mm) w
  end.

(** ** 3. Outer Cell Model *)

Record OuterCellStyle := mkOuterCell {
  oc_border_pad     : BoxEdges;
  oc_specified_h    : nat;
  oc_valign         : VerticalAlign;
  oc_inner_table    : InnerTableStyle
}.

(** Phase 1: Outer cell computes its MinMaxSizes from the inner table *)
Definition compute_outer_cell_min_width (oc : OuterCellStyle) : nat :=
  let it := oc_inner_table oc in
  let it_min := match it_width_style it with
                | WAuto => min_size (it_minmax it)
                | WFixed w => Nat.max (min_size (it_minmax it)) w
                end in
  inline_sum (oc_border_pad oc) + inline_sum (it_margins it) + it_min.

(** Phase 2: Outer cell computes its intrinsic block contribution to the outer row *)
Definition compute_outer_cell_intrinsic_height (oc : OuterCellStyle) : nat :=
  let it := oc_inner_table oc in
  let it_h := compute_inner_table_height it in
  let content_h := block_sum (oc_border_pad oc) + block_sum (it_margins it) + it_h in
  Nat.max (oc_specified_h oc) content_h.

(** ** 4. Layout Geometry & Fragment Generation *)

Record BoxGeometry := mkGeom {
  x      : nat;
  y      : nat;
  width  : nat;
  height : nat
}.

Record NestedLayoutResult := mkResult {
  outer_cell_geom  : BoxGeometry;
  inner_table_geom : BoxGeometry
}.

(** Phase 3: Final layout pass given resolved outer column width and outer row height *)
Definition layout_nested_table
  (oc : OuterCellStyle)
  (resolved_col_width : nat)
  (resolved_row_height : nat) : NestedLayoutResult :=
  let it := oc_inner_table oc in
  let cb_avail_w := resolved_col_width - inline_sum (oc_border_pad oc) in
  let it_w := resolve_inner_table_width it cb_avail_w in
  let it_h := compute_inner_table_height it in

  (* Horizontal offset of inner table relative to outer cell *)
  let it_x := left (oc_border_pad oc) + left (it_margins it) in

  (* Vertical alignment calculation (synthesized intrinsic padding) *)
  let used_content_h := block_sum (oc_border_pad oc) + block_sum (it_margins it) + it_h in
  let free_v_space := resolved_row_height - used_content_h in
  let valign_offset :=
    match oc_valign oc with
    | VTop    => 0
    | VMiddle => Nat.div2 free_v_space
    | VBottom => free_v_space
    end in
  let it_y := top (oc_border_pad oc) + top (it_margins it) + valign_offset in

  mkResult
    (mkGeom 0 0 resolved_col_width resolved_row_height)
    (mkGeom it_x it_y it_w it_h).

(** ** 5. Theorems & Invariant Proofs *)

Lemma div2_le : forall n, Nat.div2 n <= n.
Proof.
  intro n.
  pose proof (Nat.div2_decr n (Nat.le_refl n)).
  lia.
Qed.

(** Theorem 1: Outer cell height is always >= inner table height
    provided the outer row height respects the cell's intrinsic height contribution. *)
Theorem outer_cell_height_ge_inner_table_height :
  forall (oc : OuterCellStyle) (col_w row_h : nat),
    row_h >= compute_outer_cell_intrinsic_height oc ->
    let res := layout_nested_table oc col_w row_h in
    height (outer_cell_geom res) >= height (inner_table_geom res).
Proof.
  intros oc col_w row_h H_row res.
  unfold res, layout_nested_table, compute_outer_cell_intrinsic_height in *.
  simpl.
  pose proof (Nat.le_max_r (oc_specified_h oc)
    (block_sum (oc_border_pad oc) + block_sum (it_margins (oc_inner_table oc)) +
     compute_inner_table_height (oc_inner_table oc))) as H_max.
  lia.
Qed.

(** Theorem 2: Vertical Bounding Box Containment.
    The inner table's vertical coordinates [y, y + height] are strictly contained
    within [0, outer_cell_height]. *)
Theorem inner_table_vertically_contained :
  forall (oc : OuterCellStyle) (col_w row_h : nat),
    row_h >= compute_outer_cell_intrinsic_height oc ->
    let res := layout_nested_table oc col_w row_h in
    let o_geom := outer_cell_geom res in
    let i_geom := inner_table_