### 1. Core Data Structures in Blink Column Spanners

In Chromium's Blink rendering engine (specifically within the LayoutNG architecture, now the primary layout system in `third_party/blink/renderer/core/layout/`), multi-column layout and column spanners (`column-span: all`) are orchestrated via a set of specialized layout algorithms, break tokens, and path structures:

*   **`ColumnLayoutAlgorithm` (formerly `NGColumnLayoutAlgorithm`)**: The master coordinator for a multi-column container. Instead of laying out all children in a single pass, it divides the layout into alternating **column rows** (fragmented flows) and **spanner parts**. It maintains the `intrinsic_block_size_` accumulator across these segments and manages the `ConstraintSpace` configurations for both column fragments and spanners.
*   **`ColumnSpannerPath` (formerly `NGColumnSpannerPath`)**: A singly-linked tree node structure (`const LayoutInputNode` + `const ColumnSpannerPath* child`) that traces the exact ancestry chain from the multicol container down to the `column-span: all` element. Because CSS Multicol 1 §6 permits spanners to be nested inside non-spanning block-level descendants (as long as those descendants belong to the same formatting context), Blink uses this path to skip past already-processed siblings and locate the spanner during the resume phase after an interruption.
*   **`BlockBreakToken` & `MulticolBreakTokenData`**: When a child layout algorithm (such as `BlockLayoutAlgorithm` running inside a column) encounters a node with `IsColumnSpanAll()`, it cannot lay it out within the narrow column constraint space. Instead, it aborts the current fragment generation, marks the resulting `PhysicalBoxFragment` as interrupted by a spanner, and constructs a `ColumnSpannerPath` bubbling up to the root `ColumnLayoutAlgorithm`.

---

### 2. Spanner Layout Algorithm

According to **CSS Multi-column Layout Module Level 1 §6 (`column-span`)**, an element with `column-span: all` acts as a structural break in the multi-column flow. Blink executes this via an iterative state machine inside `ColumnLayoutAlgorithm::LayoutChildren()`:

1.  **Interrupting Multi-Column Fragmentation**:
    *   `ColumnLayoutAlgorithm` begins by invoking `LayoutRow()` to lay out regular column content.
    *   Inside `LayoutRow()`, columns are generated sequentially. If the depth-first traversal inside a column hits a descendant $S$ with `column-span: all`, the inner `BlockLayoutAlgorithm` immediately stops adding inflow children.
    *   It attaches $S$ to a `ColumnSpannerPath` and returns an early `LayoutResult` to `ColumnLayoutAlgorithm`. An outgoing `BlockBreakToken` is created at the exact point of interruption so the remaining content *after* the spanner can be resumed later.

2.  **Balancing Preceding Columns**:
    *   Before the spanner can be positioned, CSS Multicol §6 mandates that *"column boxes before the spanner are balanced and shortened."*
    *   `LayoutRow()` detects the pending `ColumnSpannerPath` and forces column balancing on the current row—even if the multicol container has `column-fill: auto` and a constrained `height`.
    *   It computes the balanced block size via `CalculateBalancedColumnBlockSize()`, sums the uncompressed block sizes of all content preceding the spanner, divides by the used `column-count` ($N$), and steps through minimal feasible heights until the content preceding $S$ fits into at most $N$ columns.
    *   The resulting balanced row height is added to `intrinsic_block_size_`.

3.  **Spanning Across Full Multicol Container Width**:
    *   Control transfers to `ColumnLayoutAlgorithm::LayoutSpanner(BlockNode spanner_node, const BlockBreakToken* break_token, ...)`.
    *   A new `ConstraintSpace` is constructed specifically for the spanner using `CreateConstraintSpaceForSpanner()`.
    *   Margin collapsing is resolved between the preceding column row (or preceding adjacent spanner) and the spanner's top margin (note: spanner margins do not collapse through the column row, per spec, though adjacent spanners can collapse margins with each other in certain contexts).
    *   The spanner is laid out directly into the multicol container's `BoxFragmentBuilder` at the current block offset (`intrinsic_block_size_` + resolved margin), spanning across all columns and gaps.

4.  **Resuming Columns Below**:
    *   Once `LayoutSpanner()` completes, `intrinsic_block_size_` is incremented by the spanner's border-box block size.
    *   The main loop in `LayoutChildren()` resumes. It passes the saved `BlockBreakToken` (from the interrupted column row) and the consumed `ColumnSpannerPath` into a fresh `LayoutRow()` invocation.
    *   The inner `BlockLayoutAlgorithm` uses the break token and path to fast-forward to the ancestor block of the spanner, steps past the spanner node itself, and resumes laying out subsequent inflow children into a brand new row of columns below the spanner.

---

### 3. Available Inline Size Override (`column-span: all` vs. Regular Children)

Let $W_{\text{container}}$ be the content-box inline size of the multicol container (`ChildAvailableSize().inline_size`), $N \ge 1$ be the used `column-count`, and $G \ge 0$ be the used `column-gap`.

*   **Regular Column Children (`CreateConstraintSpaceForColumns`)**:
    The inline size allocated to each column box fragment is restricted to a single column strip:
    $$W_{\text{col}} = \max\left(0,\; \frac{W_{\text{container}} - (N - 1) \cdot G}{N}\right)$$
    Regular children (and the anonymous ancestor blocks containing a nested spanner) receive `AvailableSize().inline_size` $= W_{\text{col}}$.

*   **Spanner Children (`CreateConstraintSpaceForSpanner`)**:
    When `ColumnLayoutAlgorithm` builds the `ConstraintSpace` for a spanner, it bypasses `column_inline_size` entirely and passes the full `ChildAvailableSize()` of the multicol container:
    $$W_{\text{spanner\_avail}} = W_{\text{container}} = N \cdot W_{\text{col}} + (N - 1) \cdot G$$
    Furthermore, even if the spanner is DOM-nested inside an ancestor block $B$ that has non-zero inline margins, borders, or padding, CSS Multicol 1 §6 specifies that the spanner breaks out of the flow directly to the multicol container level; thus, its available inline size is strictly $W_{\text{container}}$ (independent of $B$'s box model properties).

---

### 4. Mathematical Invariants

For any valid layout execution over a multicol container with content inline size $W_{\text{container}}$, column count $N \ge 1$, column gap $G \ge 0$, and an ordered sequence of layout items $I = [e_1, e_2, \dots, e_k]$ partitioned into column rows $R_j$ and spanners $S_m$:

1.  **Spanner Inline Size Invariant**:
    Assuming `width: auto` and zero inline margins on the spanner $S_m$:
    $$\text{InlineSize}(S_m) = W_{\text{container}} = N \cdot W_{\text{col}} + (N - 1) \cdot G$$
2.  **Spanner Block Offset Monotonicity & Preceding Balance Invariant**:
    For a spanner $S_m$ immediately preceded by a column row $R_j$ starting at block offset $Y(R_j)$ with total unfragmented content block size $H_{\text{raw}}(R_j)$:
    $$\text{BlockOffset}(S_m) \ge Y(R_j) + H_{\text{bal}}(R_j)$$
    where the balanced height satisfies the lower bound:
    $$H_{\text{bal}}(R_j) \ge \left\lceil \frac{H_{\text{raw}}(R_j)}{N} \right\rceil$$
    and similarly, for the subsequent column row $R_{j+1}$ following $S_m$:
    $$Y(R_{j+1}) \ge \text{BlockOffset}(S_m) + \text{BlockSize}(S_m)$$
3.  **Layout Determinism Invariant**:
    For any fixed multicol configuration $C = (W_{\text{container}}, N, G)$ and input node list $L$, the layout evaluation relation is a total deterministic function yielding a unique sequence of positioned fragments.

---

### 5. Rocq / Coq Formalization (`BlinkMulticolSpannerSemantics.v`)

The following complete, self-contained Coq (Rocq) development formalizes Blink's multi-column spanner layout semantics and proves the required invariants without any admitted proofs.

```coq
(** * BlinkMulticolSpannerSemantics.v
    Formalization of Chromium Blink Multi-column Spanner Layout
    audited against CSS Multi-column Layout Module Level 1, Section 6. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Dimensions and Offsets are represented as natural numbers (layout units). *)
Definition LayoutUnit := nat.

(** Multicol container geometric configuration. *)
Record MulticolConfig : Type := mkMulticolConfig {
  mc_col_width : LayoutUnit;
  mc_col_count : nat;        (* Used column-count N >= 1 *)
  mc_col_gap   : LayoutUnit
}.

(** Total content-box inline size of the multicol container:
    W_container = N * W_col + (N - 1) * G *)
Definition multicol_content_width (cfg : MulticolConfig) : LayoutUnit :=
  (mc_col_count cfg * mc_col_width cfg) +
  ((mc_col_count cfg - 1) * mc_col_gap cfg).

(** Available inline size override selector. *)
Inductive ChildKind : Type :=
  | RegularColumnChild : ChildKind
  | SpannerChild       : ChildKind.

Definition available_inline_size (cfg : MulticolConfig) (k : ChildKind) : LayoutUnit :=
  match k with
  | RegularColumnChild => mc_col_width cfg
  | SpannerChild       => multicol_content_width cfg
  end.

(** Input DOM / LayoutTree nodes inside a multicol formatting context. *)
Inductive MulticolInputNode : Type :=
  | InflowBlock : LayoutUnit (* intrinsic block size *) -> MulticolInputNode
  | SpannerBox  : LayoutUnit (* block size *) -> LayoutUnit (* top_margin *) -> MulticolInputNode
  | NestedBlock : list MulticolInputNode -> MulticolInputNode.

(** Representation of Blink's [ColumnSpannerPath]: traces ancestry from
    multicol root to the interrupting spanner node. *)
Inductive ColumnSpannerPath : Type :=
  | PathLeafAtSpanner : LayoutUnit (* block_size *) -> LayoutUnit (* margin *) -> ColumnSpannerPath
  | PathStep          : nat (* child index *) -> ColumnSpannerPath -> ColumnSpannerPath.

(** Flattened layout parts produced after resolving ColumnSpannerPaths. *)
Inductive LayoutPart : Type :=
  | ColumnRowPart : LayoutUnit (* total raw content block height *) -> LayoutPart
  | SpannerPart   : LayoutUnit (* block_size *) -> LayoutUnit (* top_margin *) -> LayoutPart.

(** Positioned output fragments inside the multicol container. *)
Record PositionedFragment : Type := mkFragment {
  frag_kind         : ChildKind;
  frag_block_offset : LayoutUnit;
  frag_inline_size  : LayoutUnit;
  frag_block_size   : LayoutUnit
}.

(** ** 2. Spanner Interruption and Column Balancing Semantics *)

(** Ceiling division helper: ceil(a / b) for b > 0. *)
Definition div_ceil (a b : nat) : nat :=
  match b with
  | 0 => 0
  | S b' => (a + b') / (S b')
  end.

(** Balanced column height for a column row preceding a spanner.
    Per CSS Multicol 1 §6, columns before a spanner are automatically balanced. *)
Definition balanced_row_height (cfg : MulticolConfig) (raw_height : LayoutUnit) : LayoutUnit :=
  div_ceil raw_height (mc_col_count cfg).

(** Flatten nested blocks by interrupting column flow whenever a SpannerBox is encountered,
    mimicking ColumnLayoutAlgorithm's interaction with ColumnSpannerPath and BreakTokens. *)
Fixpoint flatten_nodes (nodes : list MulticolInputNode) : list LayoutPart :=
  match nodes with
  | [] => []
  | (InflowBlock h) :: rest =>
      match flatten_nodes rest with
      | (ColumnRowPart h_next) :: parts' => (ColumnRowPart (h + h_next)) :: parts'
      | parts' => (ColumnRowPart h) :: parts'
      end
  | (SpannerBox h m) :: rest =>
      (SpannerPart h m) :: (flatten_nodes rest)
  | (NestedBlock children) :: rest =>
      flatten_nodes (children ++ rest)
  end.

(** Lay out a single LayoutPart at a given block offset [curr_y],
    returning the generated fragment and the updated block offset. *)
Definition layout_single_part (cfg : MulticolConfig) (curr_y : LayoutUnit) (part : LayoutPart)
  : PositionedFragment * LayoutUnit :=
  match part with
  | ColumnRowPart raw_h =>
      let bal_h := balanced_row_height cfg raw_h in
      let frag := mkFragment RegularColumnChild curr_y (available_inline_size cfg RegularColumnChild) bal_h in
      (frag, curr_y + bal_h)
  | SpannerPart span_h margin_top =>
      let span_y := curr_y + margin_top in
      let span_w := available_inline_size cfg SpannerChild in
      let frag := mkFragment SpannerChild span_y span_w span_h in
      (frag, span_y + span_h)
  end.

(** Lay out a sequence of parts iteratively (ColumnLayoutAlgorithm::LayoutChildren). *)
Fixpoint layout_parts (cfg : MulticolConfig) (curr_y : LayoutUnit) (parts : list LayoutPart)
  : list PositionedFragment * LayoutUnit :=
  match parts with
  | [] => ([], curr_y)
  | p :: ps =>
      let (frag, next_y) := layout_single_part cfg curr_y p in
      let (frags, final_y) := layout_parts cfg next_y ps in
      (frag :: frags, final_y)
  end.

(** Relational specification of the Multicol Spanner Layout Algorithm. *)
Inductive EvalMulticolLayout (cfg : MulticolConfig) :
  LayoutUnit -> list LayoutPart -> list PositionedFragment -> LayoutUnit -> Prop :=
  | Eval_Nil : forall y,
      EvalMulticolLayout cfg y [] [] y
  | Eval_ColumnRow : forall y raw_h ps frags final_y,
      let bal_h := balanced_row_height cfg raw_h in
      let frag := mkFragment RegularColumnChild y (available_inline_size cfg RegularColumnChild) bal_h in
      EvalMulticolLayout cfg (y + bal_