### 1. Unified Page Assembly Pipeline (`LocalFrameView::PerformLayout`)

In Chromium Blink's LayoutNG engine, `LocalFrameView::PerformLayout` orchestrates full-page formatting by invoking `BlockNode::Layout` on the root `LayoutView` node. The root `NGBlockLayoutAlgorithm` traverses its block-level children sequentially, maintaining a vertical cursor (`BfcBlockOffset`), resolving adjacent vertical margins via `NGMarginStrut`, and producing an immutable `NGPhysicalBoxFragment` tree.

```
LocalFrameView::PerformLayout()
  └── LayoutView (Root NGBlockLayoutAlgorithm)
        ├── [1] H1 (BlockNode)           ──> NGBlockLayoutAlgorithm (InlineFormattingContext)
        ├── [2] P (BlockNode)            ──> NGBlockLayoutAlgorithm (LineBreaker: Multi-line)
        ├── [3] Flex (BlockNode)         ──> NGFlexLayoutAlgorithm (Multi-line Flex Lines)
        ├── [4] Table (BlockNode)        ──> NGTableLayoutAlgorithm (2-Col % Distribution)
        ├── [5] UL (BlockNode)           ──> NGBlockLayoutAlgorithm + NGUnpositionedListMarker
        └── [6] Button (BlockNode)       ──> NGBlockLayoutAlgorithm (Synthesized Baseline/Box)
```

#### Sequential Element Assembly:
1. **Header 1 (`<h1>`)**: Formatted as a standard block container establishing an Inline Formatting Context (`NGInlineLayoutAlgorithm`). Its default UA stylesheet margins (`margin-block-start: 0.67em`, `margin-block-end: 0.67em`) initialize the root `NGMarginStrut`.
2. **Paragraph (`<p>`)**: The root algorithm appends `<p>`'s top margin (`1em`) to the active `NGMarginStrut` left by `<h1>`. `NGMarginStrut::Sum()` resolves the collapsed margin offset, advances the BFC block offset, and invokes `NGInlineLayoutAlgorithm` to break text runs into line boxes.
3. **Multi-line Flex Box (`display: flex; flex-wrap: wrap`)**: Invokes `NGFlexLayoutAlgorithm`. The flex container consumes the resolved margin strut from `<p>`, computes main-axis (inline) line breaking across multiple `NGFlexLine` instances, and accumulates cross-axis (block) sizes.
4. **2-Column Table with Percent Columns (`<table>`)**: Invokes `NGTableLayoutAlgorithm`. It resolves column widths by converting percentage constraints (`Col1%`, `Col2%`) against the available inline size of the root BFC, distributes remaining space, and lays out `NGTableRowLayoutAlgorithm` and cell fragments (`<td>`), ensuring horizontal cell offsets are strictly disjoint.
5. **Outside Marked List (`<ul>` / `<li>`)**: Invokes `NGBlockLayoutAlgorithm` for the list container and list items. For `list-style-position: outside`, `NGUnpositionedListMarker` computes the marker's inline offset in the negative margin/padding gutter outside the principal `<li>` block box without shifting the principal block's BFC inline offset.
6. **Styled Form Button (`<button>`)**: Treated as an atomic inline-level or block-level flex/grid-like formatting context root (`LayoutNGButton`). It resolves internal border and padding boxes (`border + padding + content`), ignores internal margin collapsing (establishes a new BFC), and commits the final physical fragment to the root container.

---

### 2. Strict Monotonic Vertical Accumulation & Margin Collapsing

Within the root `NGBlockLayoutAlgorithm`, vertical layout progresses via a state machine governed by `BfcOffset` and `NGMarginStrut`. Let $Y_i$ be the resolved `BfcBlockOffset` (top border-edge) of element $i \in \{1 \dots 6\}$, $H_i \ge 0$ be its computed border-box block-size, $M_i^{\text{top}} \ge 0$ its top margin, and $M_i^{\text{bot}} \ge 0$ its bottom margin.

```
[Element i-1]
  ├── Border Box Top:    Y_{i-1}
  ├── Border Box Height: H_{i-1}
  └── Border Box Bottom: Y_{i-1} + H_{i-1}
        │
        ├── Margin Bot:  M_{i-1}^{bot}  ┐
        │                               ├── Collapsed Margin: max(M_{i-1}^{bot}, M_i^{top})
        ├── Margin Top:  M_i^{top}      ┘
        ▼
[Element i]
  └── Border Box Top:    Y_i = Y_{i-1} + H_{i-1} + max(M_{i-1}^{bot}, M_i^{top})
```

#### Margin Collapsing Resolution (`NGMarginStrut::Sum`)
For non-negative margins in a standard document flow without negative margin pull-ups:
$$\Delta M_{i-1, i} = \max(M_{i-1}^{\text{bot}}, M_i^{\text{top}})$$

#### Cursor Advancement Equations
1. **Initial Element ($i = 1$, Header 1)**:
   $$Y_1 = \text{BorderPadding}_{\text{top}}^{\text{root}} + M_1^{\text{top}}$$
2. **Subsequent Sibling Elements ($i \in \{2 \dots 6\}$)**:
   $$Y_i = Y_{i-1} + H_{i-1} + \max(M_{i-1}^{\text{bot}}, M_i^{\text{top}})$$
3. **Root Fragment Final Block Size**:
   $$H_{\text{page}} = Y_6 + H_6 + M_6^{\text{bot}} + \text{BorderPadding}_{\text{bot}}^{\text{root}}$$

Because $H_i \ge 0$ and $\max(M_{i-1}^{\text{bot}}, M_i^{\text{top}}) \ge 0$ for all standard non-negative margins, the sequence of intervals $\{[Y_i, Y_i + H_i]\}_{i=1}^6$ satisfies strict non-overlapping vertical monotonicity:
$$\forall i \in \{1 \dots 5\}, \quad Y_i \le Y_i + H_i \le Y_{i+1}$$

---

### 3. Formal Layout Invariants

1. **Deterministic Page Fragment Dimensions**: Given an immutable `NGConstraintSpace` (fixed viewport width $W_{\text{vp}}$ and height $H_{\text{vp}}$) and deterministic input DOM styles, `PerformLayout` computes a unique, deterministic root fragment dimension pair $(W_{\text{page}}, H_{\text{page}})$.
2. **Viewport Horizontal Bounding**: Every principal block box, table column, flex item, and button border-box is horizontally bounded within the root content box $[0, W_{\text{vp}}]$. For the outside list marker, its principal list-item content box remains strictly within $[0, W_{\text{vp}}]$ while its marker box is bounded within the list's gutter $[0, X_{\text{li}}]$.
3. **Vertical Monotonic Stacking Order**: For any two elements $A$ and $B$ where $A$ precedes $B$ in the DOM tree ($1 \le \text{idx}(A) < \text{idx}(B) \le 6$), the bottom border-edge of $A$ never exceeds the top border-edge of $B$:
   $$Y_A + H_A \le Y_B$$
4. **Pairwise Disjointness of Table Cells and Button Bounds**:
   - **Intra-Table Horizontal Disjointness**: In the 2-column percentage table, Column 1 occupies $[X_{\text{c1}}, X_{\text{c1}} + W_{\text{c1}})$ and Column 2 occupies $[X_{\text{c2}}, X_{\text{c2}} + W_{\text{c2}})$, where $X_{\text{c1}} + W_{\text{c1}} \le X_{\text{c2}}$.
   - **Inter-Element Vertical Disjointness**: Because the Table ($i=4$) precedes the Button ($i=6$), and the Button has positive vertical extent ($H_6 > 0$) or is separated by the List ($i=5$), the 2D physical bounding boxes of all table cells and the button are strictly disjoint in $\mathbb{N}^2$.

---

### 4. Concrete Rocq/Coq Formalization (`BlinkInteractivePagePipelineModel.v`)

The following complete, self-contained Rocq/Coq script formalizes the entire 6-stage pipeline, its layout algorithms, margin-collapsing cursor accumulation, and mechanically proves all four core invariants without admitting any axioms.

```coq
(** * BlinkInteractivePagePipelineModel.v
    Formal verification of Chromium Blink's Capstone Interactive Page Layout
    Pipeline in LocalFrameView (LayoutNG Block, Inline, Flex, Table, List, Button). *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Geometric Primitives and Physical Fragments *)

Record Rect : Type := mkRect {
  rect_x : nat;
  rect_y : nat;
  rect_w : nat;
  rect_h : nat
}.

Definition rect_right (r : Rect) : nat := rect_x r + rect_w r.
Definition rect_bottom (r : Rect) : nat := rect_y r + rect_h r.

(** Two 1D intervals [s1, e1) and [s2, e2) are disjoint if one ends before the other begins. *)
Definition interval_disjoint (s1 e1 s2 e2 : nat) : Prop :=
  e1 <= s2 \/ e2 <= s1.

(** Two 2D rectangles are disjoint if their X-projections or Y-projections are disjoint. *)
Definition rect_disjoint (r1 r2 : Rect) : Prop :=
  interval_disjoint (rect_x r1) (rect_right r1) (rect_x r2) (rect_right r2) \/
  interval_disjoint (rect_y r1) (rect_bottom r1) (rect_y r2) (rect_bottom r2).

(** Rectangle fits horizontally within a viewport width W. *)
Definition fits_horizontally (vp_w : nat) (r : Rect) : Prop :=
  rect_right r <= vp_w.

(** ** 2. Margin Strut and Block Cursor State Machine *)

Record MarginBox : Type := mkMargins {
  m_top : nat;
  m_bot : nat
}.

(** NGMarginStrut::Sum() for non-negative standard margins. *)
Definition collapse_margins (m_prev_bot m_curr_top : nat) : nat :=
  Nat.max m_prev_bot m_curr_top.

(** ** 3. Element Style Specifications *)

Record Header1Spec : Type := mkH1Spec {
  h1_line_height : nat;
  h1_margins : MarginBox
}.

Record ParagraphSpec : Type := mkPSpec {
  p_text_width : nat;
  p_line_height : nat;
  p_margins : MarginBox
}.

Record FlexBoxSpec : Type := mkFlexSpec {
  flex_item_widths : list nat;
  flex_line_height : nat;
  flex_margins : MarginBox
}.

Record Table2ColSpec : Type := mkTableSpec {
  tbl_col1_pct : nat; (* e.g., 40 for 40% *)
  tbl_col2_pct : nat; (* e.g., 60 for 60%, sum <= 100 *)
  tbl_row_height : nat;
  tbl_margins : MarginBox
}.

Record OutsideListSpec : Type := mkListSpec {
  ul_gutter_width : nat; (* padding-inline-start reserved for outside marker *)
  ul_marker_width : nat; (* width of marker placed inside gutter *)
  ul_item_heights : list nat;
  ul_margins : MarginBox
}.

Record ButtonSpec : Type := mkButtonSpec {
  btn_content_w : nat;
  btn_content_h : nat;
  btn_pad_x : nat;
  btn_pad_y : nat;
  btn_border : nat;
  btn_margins : MarginBox
}.

Record PageStyleInput : Type := mkPageInput {
  viewport_w : nat;
  viewport_h : nat;
  in_h1 : Header1Spec;
  in_p : ParagraphSpec;
  in_flex : FlexBoxSpec;
  in_table : Table2ColSpec;
  in_list : OutsideListSpec;
  in_btn : ButtonSpec
}.

(** ** 4. Sub-Algorithm Layout Engines *)

(** [1] Header 1 Layout: Single or multi-line heading block *)
Definition layout_h1 (vp_w y_cursor : nat) (s : Header1Spec) : Rect :=
  mkRect 0 y_cursor vp_w (h1_line_height s).

(** Helper: ceiling division for line breaking *)
Definition div_ceil (num den : nat) : nat :=
  match den with
  | 0 => 1
  | S d' => (num + d') / den
  end.

(** [2] Paragraph Layout: Line breaking across viewport width *)
Definition layout_paragraph (vp_w y_cursor : nat) (s : ParagraphSpec) : Rect :=
  let lines := Nat.max 1 (div_ceil (p_text_width s) vp_w) in
  mkRect 0 y_cursor vp_w (lines * p_line_height s).

(** [3] Multi-line Flex Layout: Greedy line-wrapping accumulator *)
Fixpoint count_flex_lines (vp_w cur_w : nat) (items : list nat) : nat :=
  match items with
  | [] => 1
  | w :: rest =>
      let w_clamped := Nat.min w vp_w in
      if cur_w + w_clamped <=? vp_w then
        count_flex_lines vp_w (cur_w + w_clamped) rest
      else
        S (count_flex_lines vp_w w_clamped rest)
  end.

Definition layout_flexbox (vp_w y_cursor : nat) (s : FlexBoxSpec) : Rect :=
  let lines := count_flex_lines vp_w 0 (flex_item_widths s) in
  mkRect 0 y_cursor vp_w (lines * flex_line_height s).

(** [4] 2-Column Table Layout with Percentage Columns *)
Record TableFragment : Type := mkTableFrag {
  tbl_box : Rect;
  tbl_cell1 : Rect;
  tbl_cell2 : Rect
}.

Definition layout_table (vp_w y_cursor : nat) (s : Table2ColSpec) : TableFragment :=
  let p1 := Nat.min (tbl_col1_pct s) 100 in
  let p2 := Nat.min (tbl_col2_pct s) (100 - p1) in
  let w1 := (vp_w * p1) / 100 in
  let w2 := (vp_w * p2) / 100 in
  let h := tbl_row_height s in
  mkTableFrag
    (mkRect 0 y