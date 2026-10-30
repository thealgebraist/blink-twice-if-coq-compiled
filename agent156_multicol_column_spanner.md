### 1. Column Spanner Detection in `ColumnLayoutAlgorithm`

In Chromium Blink's LayoutNG (`third_party/blink/renderer/core/layout/column_layout_algorithm.cc`), `ColumnLayoutAlgorithm` orchestrates the formatting of multi-column containers (`multicol`) by iterating through inline/block children and grouping them into alternating column rows (`kLayoutRow`) and spanner rows.

Detection and extraction of column spanners (`column-span: all`, per CSS Multi-column Layout Module Level 1 §6) operates via a cooperative mechanism between node tree inspection and fragment tree unwinding:

1. **Qualification Criteria (`LayoutInputNode::IsColumnSpanAll`)**:
   A child box qualifies as an active column spanner if and only if:
   * Its computed style has `column-span: all` (`ComputedStyle::GetColumnSpan() == EColumnSpan::kAll`).
   * It is an in-flow block-level element (`!IsFloating() && !IsOutOfFlowPositioned() && !IsInline()`).
   * It is formatting within the same block formatting context established by the multicol container (i.e., it does not cross an ancestor boundary that establishes an independent formatting context, such as `overflow: scroll`, `display: flow-root`, `display: table`, or `display: flex/grid`).

2. **Discovery and Break Token Interruption**:
   * **Direct Child**: If `ColumnLayoutAlgorithm::Layout()` encounters a direct child where `child.IsColumnSpanAll()` is true before entering a column row, it delegates directly to `LayoutSpanner()`.
   * **Descendant inside a Column Row**: When laying out a column via `BlockLayoutAlgorithm`, if an inner descendant satisfies `IsColumnSpanAll()`, the inner algorithm halts layout of the current block immediately prior to the spanner. It sets `ConstraintSpace::ShouldPropagateChildBreakValues()` and calls `LayoutResult::SetColumnSpannerPath(spanner_path)`, attaching an `NGColumnSpannerPath` (a singly linked list of `BlockNode` pointers from the multicol container down to the spanner) and emitting an unfinished `BlockBreakToken` for the interrupted ancestor chain.

3. **Unwinding and Layout Execution**:
   `ColumnLayoutAlgorithm::LayoutRow()` detects `result->GetColumnSpannerPath()` upon completing a column fragment. It ceases generating additional columns in the current row, balances and finalizes the preceding column fragments, and returns control to the main loop in `ColumnLayoutAlgorithm::Layout()`. The main loop then invokes `LayoutSpanner(spanner_node, spanner_path, ...)` to format the spanner across the container before resuming normal column layout using the saved `BlockBreakToken`s of the interrupted flow.

---

### 2. Geometry & Coordinate Transformation

When a column spanner interrupts the multi-column flow, `ColumnLayoutAlgorithm` transitions from multi-column strip geometry to full-container block geometry:

1. **Flow Interruption & Row Finalization**:
   Let the multicol container have content-box inline size $W_{\text{multicol}}$, column inline size $W_{\text{col}}$, column gap $G$, and column count $N \ge 1$, where $W_{\text{col}} = \frac{W_{\text{multicol}} - (N - 1)G}{N}$.
   When a spanner is encountered, all in-flow content preceding the spanner is balanced across the current row of columns $c_0, c_1, \dots, c_{k-1}$ ($k \le N$). The block-size of this preceding column row is computed as:
   $$H_{\text{row\_pre}} = \max_{0 \le i < k} (\text{BlockSize}(c_i))$$
   The intrinsic block size accumulator `intrinsic_block_size_` advances by $H_{\text{row\_pre}}$.

2. **Spanner Constraint Space & Inline Size**:
   Inside `ColumnLayoutAlgorithm::LayoutSpanner()`, a dedicated `ConstraintSpace` is constructed for the spanner node via `CreateConstraintSpaceForSpanner()`:
   * The available inline size passed to the spanner is set directly to the multicol container's content-box inline size: $W_{\text{avail}} = W_{\text{multicol}}$.
   * Column count $N$ and column gap $G$ are completely bypassed.
   * For a standard box filling its available inline size (with horizontal margins $M_{\text{inline}} = 0$), the resulting fragment inline size is:
     $$W_{\text{span}} = W_{\text{multicol}}$$

3. **Block Axis Placement & Resumption**:
   * **Preceding Offset**: Let $Y_{\text{row\_pre}}$ be the block-start offset of the preceding column row. After the preceding row finishes, the running block offset is $Y_{\text{pre\_end}} = Y_{\text{row\_pre}} + H_{\text{row\_pre}}$.
   * **Spanner Offset**: After resolving block-axis margins ($M_{\text{top}}, M_{\text{bottom}}$, which collapse with adjacent spanners or container boundaries according to Blink's `MarginStrut`, though not across column row boundaries), the spanner is placed at:
     $$Y_{\text{span}} = Y_{\text{pre\_end}} + M_{\text{top}}$$
   * **Subsequent Column Row Offset**: Once the spanner produces a fragment of block size $H_{\text{span}}$, `intrinsic_block_size_` advances to $Y_{\text{span}} + H_{\text{span}} + M_{\text{bottom}}$. The next column row (resuming from the interrupted `BlockBreakToken`) is placed at:
     $$Y_{\text{row\_post}} = Y_{\text{span}} + H_{\text{span}} + M_{\text{bottom}}$$

---

### 3. Formal Invariants

For any valid execution of `ColumnLayoutAlgorithm` over a sequence of flow items containing a column spanner $S$:

* **Invariant 1 (Full-Width Inline Span)**:
  The available inline size allocated to $S$ equals the content-box inline size of the multicol container, invariant to $N$ and $G$:
  $$W_{\text{span}} = W_{\text{multicol}} \ge W_{\text{col}} \quad (\text{for } N \ge 1, G \ge 0)$$

* **Invariant 2 (Strict Block-Axis Ordering after Preceding Columns)**:
  For every column fragment $c_i$ in the column row immediately preceding $S$ (placed at block offset $Y_{\text{row\_pre}}$ with non-negative margins $M_{\text{top}} \ge 0$):
  $$Y_{\text{span}} \ge Y_{\text{row\_pre}} + \text{BlockSize}(c_i)$$

* **Invariant 3 (Strict Block-Axis Resumption for Subsequent Columns)**:
  If in-flow content remains after $S$ and generates a subsequent column row at offset $Y_{\text{row\_post}}$ (with $M_{\text{bottom}} \ge 0$ and $H_{\text{span}} \ge 0$):
  $$Y_{\text{row\_post}} \ge Y_{\text{span}} + H_{\text{span}}$$

* **Invariant 4 (Pairwise Non-Overlapping Block Intervals)**:
  The block-axis intervals occupied by the preceding column row $[Y_{\text{row\_pre}}, Y_{\text{row\_pre}} + H_{\text{row\_pre}})$, the spanner $[Y_{\text{span}}, Y_{\text{span}} + H_{\text{span}})$, and the subsequent column row $[Y_{\text{row\_post}}, Y_{\text{row\_post}} + H_{\text{row\_post}})$ are strictly disjoint and monotonically ordered.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkMulticolColumnSpannerSemantics.v`)

```coq
(** * BlinkMulticolColumnSpannerSemantics.v
    Formal verification of Chromium Blink's ColumnLayoutAlgorithm
    for CSS Multi-column Layout Module Level 1 §6 (Column Spanners). *)

From Coq Require Import Arith ZArith List Bool Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Style and Node Qualification Model *)

Inductive EColumnSpan : Type :=
  | kNone
  | kAll.

Record NodeStyle : Type := mkNodeStyle {
  column_span : EColumnSpan;
  is_in_flow : bool;
  is_block_level : bool;
  in_multicol_bfc : bool (* False if inside an intermediate independent BFC *)
}.

(** Matches LayoutInputNode::IsColumnSpanAll() in Blink *)
Definition is_column_span_all (s : NodeStyle) : bool :=
  match s.(column_span) with
  | kAll => s.(is_in_flow) && s.(is_block_level) && s.(in_multicol_bfc)
  | kNone => false
  end.

(** ** 2. Multi-Column Container & Flow Item Geometry *)

Record MulticolConfig : Type := mkMulticolConfig {
  w_multicol : Z;   (* Container content-box inline size *)
  col_count  : Z;   (* Computed column-count N >= 1 *)
  col_gap    : Z;   (* Computed column-gap G >= 0 *)
  wf_width   : w_multicol >= 0;
  wf_count   : col_count >= 1;
  wf_gap     : col_gap >= 0
}.

(** Computes column inline size: max(0, (W_multicol - (N - 1)*G) / N) *)
Definition compute_column_inline_size (cfg : MulticolConfig) : Z :=
  Z.max 0 ((cfg.(w_multicol) - (cfg.(col_count) - 1) * cfg.(col_gap)) / cfg.(col_count)).

(** Flow items processed by ColumnLayoutAlgorithm::Layout() *)
Inductive MulticolChild : Type :=
  | FlowColumnRow (col_heights : list Z)
  | SpannerBox (style : NodeStyle) (block_size : Z) (m_top : Z) (m_bottom : Z).

(** ** 3. Layout Fragment Output Representation *)

Inductive FragmentKind : Type :=
  | FragColumnRow (col_heights : list Z)
  | FragSpanner.

Record PlacedFragment : Type := mkPlacedFragment {
  frag_kind        : FragmentKind;
  frag_inline_size : Z;
  frag_block_start : Z;
  frag_block_size  : Z
}.

(** ** 4. ColumnLayoutAlgorithm Execution Semantics *)

Fixpoint max_list_Z (l : list Z) : Z :=
  match l with
  | [] => 0
  | x :: xs => Z.max x (max_list_Z xs)
  end.

(** Layout of a single column row: ColumnLayoutAlgorithm::LayoutRow *)
Definition layout_column_row (cfg : MulticolConfig) (y_cursor : Z) (col_heights : list Z)
  : PlacedFragment * Z :=
  let h_row := max_list_Z col_heights in
  let w_col := compute_column_inline_size cfg in
  let frag := mkPlacedFragment (FragColumnRow col_heights) w_col y_cursor h_row in
  (frag, y_cursor + h_row).

(** Layout of a column spanner: ColumnLayoutAlgorithm::LayoutSpanner *)
Definition layout_spanner (cfg : MulticolConfig) (y_cursor : Z)
                          (h_span m_top m_bottom : Z)
  : PlacedFragment * Z :=
  let y_span := y_cursor + m_top in
  let w_span := cfg.(w_multicol) in
  let frag := mkPlacedFragment FragSpanner w_span y_span h_span in
  (frag, y_span + h_span + m_bottom).

(** Main step function of ColumnLayoutAlgorithm::Layout *)
Definition layout_step (cfg : MulticolConfig) (y_cursor : Z) (child : MulticolChild)
  : PlacedFragment * Z :=
  match child with
  | FlowColumnRow col_heights =>
      layout_column_row cfg y_cursor col_heights
  | SpannerBox style h_span m_top m_bottom =>
      if is_column_span_all style then
        layout_spanner cfg y_cursor h_span m_top m_bottom
      else
        (* Non-qualifying spanner falls back to single column in-flow placement *)
        layout_column_row cfg y_cursor [m_top + h_span + m_bottom]
  end.

Fixpoint layout_children (cfg : MulticolConfig) (y_cursor : Z) (children : list MulticolChild)
  : list PlacedFragment * Z :=
  match children with
  | [] => ([], y_cursor)
  | c :: cs =>
      let (frag, y_next) := layout_step cfg y_cursor c in
      let (frags, y_final) := layout_children cfg y_next cs in
      (frag :: frags, y_final)
  end.

(** ** 5. Proofs of CSS Multi-column 1 §6 Invariants *)

Lemma max_list_Z_nonneg : forall l,
  max_list_Z l >= 0.
Proof.
  induction l as [|x xs IH]; simpl; lia.
Qed.

Lemma max_list_Z_ub : forall l x,
  In x l -> x <= max_list_Z l.
Proof.
  induction l as [|h t IH]; intros x HIn; simpl in *.
  - contradiction.
  - destruct HIn as [Heq | HIn].
    + subst; lia.
    + specialize (IH x HIn); lia.
Qed.

(** Theorem 1: Spanner inline size equals full multicol inline size W_multicol,
    ignoring column count and gaps, and is always >= column inline size. *)
Theorem spanner_inline_size_invariant :
  forall (cfg : MulticolConfig) (y_cursor h_span m_top m_bottom : Z)
         (frag : PlacedFragment) (y_next : Z),
    layout_spanner cfg y_cursor h_span m_top m_bottom = (frag, y_next) ->
    frag.(frag_inline_size) = cfg.(w_multicol) /\
    frag.(frag_inline_size) >= compute_column_inline_size cfg.
Proof.
  intros cfg y_cursor h_span m_top m_bottom frag y_next Hlayout.
  unfold layout_spanner in Hlayout.
  inversion Hlayout; subst; clear Hlayout.
  simpl. split.
  - reflexivity.
  - unfold compute_column_inline_size.
    pose proof (cfg.(wf_width)) as Hw.
    pose proof (cfg.(wf_count)) as Hc.
    pose proof (cfg.(wf_gap)) as Hg.
    apply Z.ge_le_iff.
    apply Z.max_lub; [lia |].
    assert (Hsub : cfg.(w_multicol) - (cfg.(col_count) - 1) * cfg.(col_gap) <= cfg.(w_multicol)) by nia.
    assert (Hdiv : (cfg.(w_multicol) - (cfg.(col_count) - 1) * cfg.(col