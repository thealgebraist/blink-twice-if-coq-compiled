### 1. Core Data Structures in Chromium Blink

In Chromium's LayoutNG table architecture, row stacking and height accumulation occur across two coordination layers: `TableLayoutAlgorithm` (which computes global table geometry and distributes vertical height across sections/rows) and `TableSectionLayoutAlgorithm` (which places the individual row fragments within a `<tbody>`, `<thead>`, or `<tfoot>`).

#### A. `TableTypes::Row` (`third_party/blink/renderer/core/layout/table/table_types.h`)
Before fragments are generated, `TableTypes::Row` stores the resolved geometric metrics for each row across the entire table:
```cpp
struct Row {
  LayoutUnit block_size;          // Final computed height of row k: row_height(k)
  wtf_size_t start_cell_index;
  wtf_size_t cell_count;
  LayoutUnit baseline;
  bool is_constrained;            // True if row has fixed CSS height
  bool has_rowspan_start;
  bool is_collapsed;              // True if visibility: collapse
};
```

#### B. `TableSectionLayoutAlgorithm` (`table_section_layout_algorithm.h` / `.cc`)
This algorithm takes an array of computed `TableTypes::Row` structures via the `TableSectionConstraintSpaceData` and generates physical fragments for each row, positioning them along the block axis (vertical axis in `horizontal-tb`).
```cpp
class CORE_EXPORT TableSectionLayoutAlgorithm
    : public LayoutAlgorithm<TableNode, BoxFragmentBuilder, BlockBreakToken> {
 public:
  explicit TableSectionLayoutAlgorithm(const LayoutAlgorithmParams& params);
  const LayoutResult* Layout();
};
```

#### C. `LayoutResult` & `PhysicalBoxFragment` (Row Layout Result)
Blink does not use a standalone `RowLayoutResult` class; rather, `TableRowLayoutAlgorithm::Layout()` returns a `const LayoutResult*` wrapping a `PhysicalBoxFragment`. When `TableSectionLayoutAlgorithm` iterates over its child rows, it invokes `row.Layout(...)` to obtain this result, and registers the fragment with its `BoxFragmentBuilder` (`container_builder_`) at a specific `LogicalOffset`:
```cpp
struct LogicalOffset {
  LayoutUnit inline_offset; // Typically 0 within the section
  LayoutUnit block_offset;  // The accumulated y-coordinate: row_y(k)
};
```

---

### 2. The Blink Row Stacking Algorithm

Per **CSS 2.1 §17.5.3 (Table height algorithms)**, the height of a table is given by the sum of the row heights plus any cell spacing or borders. In Blink, vertical border-spacing (`v_spacing`) is handled at two levels:
1. **Within a Section:** `TableSectionLayoutAlgorithm` places row $0$ at `block_offset = 0` (relative to the section) and interposes `v_spacing` *between* adjacent non-collapsed rows.
2. **Table-Wide:** `TableLayoutAlgorithm` places `v_spacing` before the first section, between adjacent sections, and after the last section.

When flattened to a single section (or a unified sequence of $M$ rows within the table's border box), the stacking recurrence implemented in `TableSectionLayoutAlgorithm::Layout()` (`table_section_layout_algorithm.cc`) is:

```cpp
LayoutUnit offset_y = v_spacing; // Initial top border-spacing at table level
for (wtf_size_t row_index = 0; row_index < total_rows; ++row_index) {
  const TableTypes::Row& row = rows[row_index];
  
  // Record current row's starting block offset: row_y(k)
  row_offsets[row_index] = offset_y;
  
  // Advance offset by row height and vertical border-spacing:
  // row_y(k+1) = row_y(k) + row_height(k) + border_spacing_v
  offset_y += row.block_size + v_spacing;
}
LayoutUnit total_table_content_height = offset_y;
```

#### Explicit Recurrence Relation
For a table with $M$ rows indexed $k \in \{0, \dots, M-1\}$, row heights $H(k) \ge 0$, and vertical border-spacing $S_v \ge 0$:
$$\text{row\_y}(0) = S_v$$
$$\text{row\_y}(k+1) = \text{row\_y}(k) + H(k) + S_v \quad \text{for } 0 \le k < M$$

The closed-form position of row $k$ is:
$$\text{row\_y}(k) = (k + 1) \cdot S_v + \sum_{i=0}^{k-1} H(i)$$

---

### 3. Mathematical Invariants

To audit Blink against CSS 2.1 §17.5.3, the layout engine must satisfy two primary geometric invariants:

1. **Monotonicity of Row Offsets:**
   * **Weak Monotonicity (Non-overlapping / Order Preservation):** If $\forall k, H(k) \ge 0$ and $S_v \ge 0$, then:
     $$\forall k, \quad \text{row\_y}(k+1) \ge \text{row\_y}(k)$$
   * **Strict Monotonicity:** In CSS 2.1, row heights and border-spacings cannot be negative. If either the row has positive height ($H(k) > 0$) or vertical border-spacing is strictly positive ($S_v > 0$), row offsets are strictly increasing:
     $$\forall k, \quad H(k) + S_v > 0 \implies \text{row\_y}(k+1) > \text{row\_y}(k)$$

2. **Conservation of Total Table Height (CSS 2.1 §17.5.3):**
   For a table containing $M$ rows, there are $M-1$ internal row gaps, $1$ top gap (between the table top border and row $0$), and $1$ bottom gap (between row $M-1$ and the table bottom border), totaling $M+1$ vertical spacing intervals. The total accumulated block size after placing all $M$ rows must exactly equal:
   $$\text{TotalHeight}(M) = \sum_{k=0}^{M-1} H(k) + (M + 1) \cdot S_v$$

---

### 4. Concrete Rocq / Coq Formalization

Below is the complete, self-contained Rocq (Coq) formalization for `BlinkTableRowHeightAccumulationSemantics.v`. It uses Peano naturals (`nat`) and `Lia` to model `LayoutUnit` ticks (which are fixed-point integers in Blink).

```coq
(** * BlinkTableRowHeightAccumulationSemantics.v
    Formal Audit of Chromium Blink Table Row Stacking vs CSS 2.1 §17.5.3
    Agent 110 - LayoutNG Table Verification Suite *)

From Coq Require Import Arith.Arith.
From Coq Require Import Lists.List.
From Coq Require Import Micromechanics.Lia.
Import ListNotations.

Section TableRowStacking.

  (** [LayoutUnit] in Blink is a 32-bit fixed-point integer (1/64th pixel).
      Since CSS 2.1 §17.5.3 forbids negative row heights and negative 
      border-spacing, we model non-negative LayoutUnits using [nat]. *)
  Definition LayoutUnit := nat.

  (** A Row is characterized by its computed block-size (height). *)
  Record Row := mkRow {
    row_height : LayoutUnit
  }.

  (** Vertical border-spacing (border-spacing_v). *)
  Variable border_spacing_v : LayoutUnit.

  (** ** 1. Recurrence Definitions *)

  (** [row_y rows k] computes the block-offset of the k-th row (0-indexed).
      Base case: row_y(0) = border_spacing_v (top table spacing).
      Step case: row_y(k+1) = row_y(k) + row_height(k) + border_spacing_v. *)
  Fixpoint row_y (rows : list Row) (k : nat) : LayoutUnit :=
    match k, rows with
    | 0, _ => border_spacing_v
    | S k', [] => border_spacing_v
    | S k', r :: rs => (row_y rs k') + (row_height r) + border_spacing_v
    end.

  (** Alternative operational definition matching Blink's iterative loop
      in [TableSectionLayoutAlgorithm::Layout()]. *)
  Fixpoint accumulate_rows (rows : list Row) (current_y : LayoutUnit) : LayoutUnit :=
    match rows with
    | [] => current_y
    | r :: rs => accumulate_rows rs (current_y + row_height r + border_spacing_v)
    end.

  (** Total height of the table content box after stacking all M rows. *)
  Definition total_table_height (rows : list Row) : LayoutUnit :=
    accumulate_rows rows border_spacing_v.

  (** Sum of all row heights in the table. *)
  Fixpoint sum_row_heights (rows : list Row) : LayoutUnit :=
    match rows with
    | [] => 0
    | r :: rs => row_height r + sum_row_heights rs
    end.

  (** Inductive relational specification of Blink's row placement state machine. *)
  Inductive BlinkRowStackingStep : LayoutUnit -> Row -> LayoutUnit -> Prop :=
    | Step_Row : forall y_curr r y_next,
        y_next = y_curr + row_height r + border_spacing_v ->
        BlinkRowStackingStep y_curr r y_next.

  Inductive BlinkSectionTrace : LayoutUnit -> list Row -> LayoutUnit -> Prop :=
    | Trace_Nil : forall y,
        BlinkSectionTrace y [] y
    | Trace_Cons : forall y_start r rs y_mid y_end,
        BlinkRowStackingStep y_start r y_mid ->
        BlinkSectionTrace y_mid rs y_end ->
        BlinkSectionTrace y_start (r :: rs) y_end.

  (** ** 2. Equivalence of Functional and Relational Semantics *)

  Theorem accumulate_rows_trace_iff : forall rows y_start y_end,
    BlinkSectionTrace y_start rows y_end <->
    accumulate_rows rows y_start = y_end.
  Proof.
    induction rows as [| r rs IH]; intros y_start y_end; split; intro H.
    - inversion H; subst; reflexivity.
    - simpl in H; subst; constructor.
    - inversion H; subst. inversion H2; subst.
      simpl. apply IH. assumption.
    - simpl in H. apply Trace_Cons with (y_mid := y_start + row_height r + border_spacing_v).
      + constructor; reflexivity.
      + apply IH. assumption.
  Qed.

  (** ** 3. Mathematical Invariants & Verification *)

  (** Exact step equation: row_y(k+1) = row_y(k) + height(k) + spacing *)
  Lemma nth_row_step : forall (rows : list Row) (k : nat) (default_r : Row),
    k < length rows ->
    row_y rows (S k) = row_y rows k + row_height (nth k rows default_r) + border_spacing_v.
  Proof.
    induction rows as [| r rs IH]; intros k default_r Hlen.
    - simpl in Hlen. lia.
    - destruct k as [| k'].
      + simpl. lia.
      + simpl in Hlen.
        assert (Hk' : k' < length rs) by lia.
        simpl. rewrite (IH k' default_r Hk').
        lia.
  Qed.

  (** Invariant 1a: Weak Monotonicity (row_y(k+1) >= row_y(k)) *)
  Theorem row_y_monotonic_weak : forall (rows : list Row) (k : nat),
    k < length rows ->
    row_y rows k <= row_y rows (S k).
  Proof.
    intros rows k Hlen.
    pose proof (nth_row_step rows k (mkRow 0) Hlen) as Hstep.
    lia.
  Qed.

  (** Invariant 1b: Strict Monotonicity (row_y(k+1) > row_y(k))
      Holds whenever vertical border-spacing is positive OR the row has positive height. *)
  Theorem row_y_monotonic_strict : forall (rows : list Row) (k : nat) (default_r : Row),
    k < length rows ->
    (border_spacing_v > 0 \/ row_height (nth k rows default_r) > 0) ->
    row_y rows k < row_y rows (S k).
  Proof.
    intros rows k default_r Hlen Hpos.
    pose proof (nth_row_step rows k default_r Hlen) as Hstep.
    lia.
  Qed.

  (** Helper lemma generalizing the accumulator starting offset. *)
  Lemma accumulate_rows_closed_form : forall (rows : list Row) (init_y : LayoutUnit),
    accumulate_rows rows init_y =
    init_y + sum_row_heights rows + (length rows) * border_spacing_v.
  Proof.
    induction rows as [| r rs IH]; intros init_y.
    - simpl. lia.
    - simpl. rewrite IH. lia.
  Qed.

  (** Invariant 2: Total Table Height Conservation (CSS 2.1 §17.5.3)
      Total height of a table with M rows equals the sum of all M row heights
      plus (M + 1) * border_spacing_v. *)
  Theorem total_table_height_invariant : forall (rows : list Row),
    let M := length rows in
    total_table_height rows =
      sum_row_heights rows + (M + 1) * border_spacing_v.
  Proof.
    intros rows M.
    unfold total_table_height, M.
    rewrite accumulate_rows_closed_form.
    lia.
  Qed.

  (** Terminal boundary correspondence:
      The total table height is identical to the theoretical offset of row M. *)
  Theorem total_height_equals_row_y_M : forall (rows : list Row),
    total_table_height rows = row_y rows (length rows).
  Proof.
    induction rows as [| r rs IH].
    - unfold total_table_height. simpl. reflexivity.
    - simpl. rewrite <- IH.
      unfold total_table_height.
      rewrite !accumulate_rows_closed_form.
      lia.
  Qed.

End TableRowStacking.
```