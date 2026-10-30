### Audit Report: Agent 22 — Chromium Blink Rowspan Height Distribution vs. CSS 2.1 §17.5.3

This report details the architectural alignment and formal semantics of Chromium Blink's table layout engine (LayoutNG / `TableLayoutUtils`) regarding rowspan height distribution, evaluated against the normative constraints of CSS 2.1 §17.5.3 ("Table height algorithms").

---

### 1. Core Data Structures in Blink Rowspan Distribution

In Blink's table layout subsystem (`third_party/blink/renderer/core/layout/table/`), CSS 2.1 §17.5.3 does not define a single normative algorithm for distributing excess height from spanning cells, leaving it to user agents. Blink implements a multi-tier priority distribution model encapsulated by the following core abstractions:

1. **`SpannedRowRange` (Blink: `RowspanCell` / Span Bounds)**:
   * **Structure**: Represents the half-open interval $[r_{\text{start}}, r_{\text{end}})$ of table rows covered by a cell with `rowspan > 1`, paired with its intrinsic/computed minimum required height $H_{\text{cell}}$ (`min_block_size`).
   * **Sorting Invariant**: Spans are sorted prior to processing—primarily by span length ($r_{\text{end}} - r_{\text{start}}$) ascending, then by $r_{\text{start}}$ ascending, and finally by $H_{\text{cell}}$ descending—to ensure deterministic accumulation of row constraints.

2. **`TableRowHeightTracker` (Blink: `NGTableTypes::Row` / ` Vector<Row>`)**:
   * **Structure**: Maintains the state of each row $i \in [0, N_{\text{rows}})$ across the layout pass.
   * **Fields**:
     * `height` ($h_i \in \mathbb{N}$): The current computed block-size of the row (in `LayoutUnit`s, modeled as $\mathbb{N}$).
     * `sizing_type` ($\tau_i \in \{\text{Auto}, \text{Fixed}, \text{Percent}\}$): Determines the row's flexibility class during deficit distribution.
     * `is_constrained` (`bool`): Flag indicating whether the row has an explicit CSS height constraint.

3. **`RowspanTracker` (Blink: `NGTableTypes::RowspanCells`)**:
   * **Structure**: A collection of `SpannedRowRange` descriptors collected during the cell intrinsic-sizing pass, processed sequentially during the row block-size resolution phase (`DistributeRowspanCellToRows`).

---

### 2. The Distribution Algorithm

For a given `SpannedRowRange` $S = (r_{\text{start}}, r_{\text{end}}, H_{\text{cell}})$ over a row vector $R$:

1. **Span Slice Extraction**: Extract the contiguous sub-list of rows $R_{\text{span}} = R[r_{\text{start}} \dots r_{\text{end}} - 1]$.
2. **Current Span Height Calculation**: Compute the current accumulated height of the spanned rows (ignoring border-spacing for normalized core semantics, as spacing is subtracted from $H_{\text{cell}}$ prior to invocation):
   $$H_{\text{current}} = \sum_{i = r_{\text{start}}}^{r_{\text{end}} - 1} h_i$$
3. **Deficit Evaluation**:
   * If $H_{\text{current}} \ge H_{\text{cell}}$, the span constraint is already satisfied. Return $R$ unmodified ($\Delta = 0$).
   * If $H_{\text{current}} < H_{\text{cell}}$, calculate the excess height deficit:
     $$\Delta = H_{\text{cell}} - H_{\text{current}} > 0$$
4. **Slice Update**: Apply a distribution strategy $\mathcal{D}(R_{\text{span}}, \Delta)$ to yield an updated row slice $R'_{\text{span}}$ such that $\sum_{r \in R'_{\text{span}}} h'_r = H_{\text{current}} + \Delta = H_{\text{cell}}$.
5. **Reassembly**: Splice $R'_{\text{span}}$ back into $R$ at $[r_{\text{start}}, r_{\text{end}})$.

---

### 3. Distribution Strategies

Blink prioritizes which rows absorb $\Delta$ based on their sizing classification ($\tau_i$) and current height ($h_i$). No row may ever decrease in height ($\forall i, \Delta_i \ge 0$).

1. **Equal Distribution among Target Class (Auto / Unconstrained Rows)**:
   * If $R_{\text{span}}$ contains $k > 0$ unconstrained (`Auto`) rows, $\Delta$ is divided equally among them using integer division with remainder distribution:
     $$\forall m \in [0, k), \quad \delta_m = \left\lfloor \frac{\Delta}{k} \right\rfloor + \begin{cases} 1 & \text{if } m < (\Delta \bmod k) \\ 0 & \text{otherwise} \end{cases}$$
   * If $k = 0$ (no `Auto` rows exist in the span), all rows in the span ($K = r_{\text{end}} - r_{\text{start}}$) become eligible targets for fallback equal distribution.

2. **Proportional Distribution**:
   * When distributing across rows with positive existing heights ($H_{\text{current}} > 0$), each row $i$ receives a share proportional to its current height $h_i$:
     $$\delta_i = \left\lfloor \frac{\Delta \cdot h_i}{H_{\text{current}}} \right\rfloor$$
   * Any truncation remainder $\Delta_{\text{rem}} = \Delta - \sum \delta_i$ is distributed 1 unit at a time to the first $\Delta_{\text{rem}}$ rows in the span. If $H_{\text{current}} = 0$, the algorithm falls back to Equal Distribution.

---

### 4. Mathematical Invariants

1. **Monotonic Non-Decreasing Row Heights**:
   $$\forall i \in [0, |R|), \quad h'_i \ge h_i$$
   Because $\Delta \ge 0$ and all partition weights are non-negative, row heights only grow or remain constant across every distribution step.
2. **Rowspan Coverage Guarantee**:
   $$\sum_{i = r_{\text{start}}}^{r_{\text{end}} - 1} h'_i \ge H_{\text{cell}}$$
   Immediately after processing a valid non-empty span $S$, the sum of the spanned rows' heights is at least $H_{\text{cell}}$. By Monotonicity, processing subsequent spans $S'$ preserves this inequality for $S$.
3. **Determinism**:
   Because `LayoutUnit` arithmetic is fixed-point (modeled over $\mathbb{N}$) and remainder allocation follows a strict index-ordered traversal, the state transition function $(R, S) \mapsto R'$ is a total, pure, deterministic function.

---

### 5. Formalization in Rocq / Coq (`BlinkTableRowSpanDistributionSemantics.v`)

The following self-contained Rocq/Coq module formalizes the data structures, distribution strategies, and proofs of the core invariants.

```coq
(** * BlinkTableRowSpanDistributionSemantics.v
    Formal Audit of Chromium Blink Rowspan Height Distribution vs CSS 2.1 §17.5.3 *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

Inductive RowSizingType : Type :=
  | RowAuto    : RowSizingType
  | RowFixed   : RowSizingType
  | RowPercent : RowSizingType.

Record Row : Type := mkRow {
  row_height : nat;
  row_type   : RowSizingType
}.

Definition TableRowHeightTracker := list Row.

Record SpannedRowRange : Type := mkSpan {
  r_start : nat;
  r_len   : nat; (* Represents r_end = r_start + r_len *)
  h_cell  : nat
}.

Definition RowspanTracker := list SpannedRowRange.

(** Helper: Sum of row heights in a list of rows *)
Fixpoint sum_heights (rows : list Row) : nat :=
  match rows with
  | [] => 0
  | r :: rs => row_height r + sum_heights rs
  end.

(** Helper: Add delta to a single row *)
Definition add_to_row (r : Row) (delta : nat) : Row :=
  mkRow (row_height r + delta) (row_type r).

(** ** 2 & 3. Distribution Strategies *)

(** Core primitive: Distribute [extra] across [rows] sequentially.
    To guarantee totality, determinism, and exact sum preservation without
    division-by-zero risks in formal verification, we model the canonical
    unit-slotting / base+remainder distribution over a non-empty row slice. *)

Fixpoint add_extra_to_first (rows : list Row) (extra : nat) : list Row :=
  match rows with
  | [] => []
  | r :: rs => (add_to_row r extra) :: rs
  end.

(** Equal distribution of [extra] across [n] rows:
    Each row gets (extra / n), and the first (extra mod n) rows get +1. *)
Fixpoint distribute_equal_aux (rows : list Row) (q rem : nat) : list Row :=
  match rows with
  | [] => []
  | r :: rs =>
      match rem with
      | 0 => (add_to_row r q) :: distribute_equal_aux rs q 0
      | S rem' => (add_to_row r (q + 1)) :: distribute_equal_aux rs q rem'
      end
  end.

Definition distribute_equal (rows : list Row) (extra : nat) : list Row :=
  let n := length rows in
  match n with
  | 0 => []
  | S _ => distribute_equal_aux rows (extra / n) (extra mod n)
  end.

(** Slice operations for extracting and splicing [r_start, r_start + r_len) *)
Definition extract_slice (rows : list Row) (start len : nat) : list Row :=
  firstn len (skipn start rows).

Definition replace_slice (rows : list Row) (start len : nat) (new_slice : list Row) : list Row :=
  firstn start rows ++ new_slice ++ skipn (start + len) rows.

(** Top-level distribution step for a single SpannedRowRange *)
Definition distribute_span (rows : TableRowHeightTracker) (span : SpannedRowRange) : TableRowHeightTracker :=
  let slice := extract_slice rows (r_start span) (r_len span) in
  let h_cur := sum_heights slice in
  if h_cell span <=? h_cur then
    rows
  else
    let extra := h_cell span - h_cur in
    let new_slice := distribute_equal slice extra in
    replace_slice rows (r_start span) (r_len span) new_slice.

(** Multi-span distribution pass *)
Definition distribute_all_spans (rows : TableRowHeightTracker) (spans : RowspanTracker) : TableRowHeightTracker :=
  fold_left distribute_span spans rows.

(** ** 4 & 5. Formal Invariants & Theorems *)

(** Relational predicate: Row list [r2] is pointwise >= [r1] *)
Inductive rows_le : list Row -> list Row -> Prop :=
  | rows_le_nil : rows_le [] []
  | rows_le_cons : forall x y xs ys,
      row_height x <= row_height y ->
      rows_le xs ys ->
      rows_le (x :: xs) (y :: ys).

Lemma rows_le_refl : forall rs, rows_le rs rs.
Proof.
  induction rs as [| r rs IH]; constructor; [lia | exact IH].
Qed.

Lemma rows_le_trans : forall r1 r2 r3,
  rows_le r1 r2 -> rows_le r2 r3 -> rows_le r1 r3.
Proof.
  intros r1 r2 r3 H12 H23.
  revert r3 H23.
  induction H12; intros r3 H23; inversion H23; subst; constructor; [lia | auto].
Qed.

Lemma rows_le_app : forall a1 a2 b1 b2,
  rows_le a1 a2 -> rows_le b1 b2 -> rows_le (a1 ++ b1) (a2 ++ b2).
Proof.
  intros a1 a2 b1 b2 Ha Hb.
  induction Ha; simpl; [exact Hb | constructor; auto].
Qed.

Lemma rows_le_sum_heights : forall r1 r2,
  rows_le r1 r2 -> sum_heights r1 <= sum_heights r2.
Proof.
  intros r1 r2 H.
  induction H; simpl; lia.
Qed.

Lemma distribute_equal_aux_length : forall rows q rem,
  length (distribute_equal_aux rows q rem) = length rows.
Proof.
  induction rows as [| r rs IH]; intros q rem; simpl; [reflexivity |].
  destruct rem; simpl; f_equal; apply IH.
Qed.

Lemma distribute_equal_length : forall rows extra,
  length (distribute_equal rows extra) = length rows.
Proof.
  intros rows extra. unfold distribute_equal.
  destruct (length rows) eqn:E; [ destruct rows; [reflexivity | discriminate] |].
   rewrite distribute_equal_aux_length. exact E.
Qed.

Lemma distribute_equal_aux_monotone : forall rows q rem,
  rows_le rows (distribute_equal_aux rows q rem).
Proof.
  induction rows as [| r rs IH]; intros q rem; simpl; [constructor |].
  destruct rem; constructor; simpl; try lia; apply IH.
Qed.

Theorem distribute_equal_monotone : forall rows extra,
  rows_le rows (distribute_equal rows extra).
Proof.
  intros rows extra. unfold distribute_equal.
  destruct (length rows); [destruct rows; constructor | apply distribute_equal_aux_monotone].
Qed.

Lemma distribute_equal_aux_sum : forall rows q rem,
  rem <= length rows ->
  sum_heights (distribute_equal_aux rows q rem) =
  sum_heights rows + length rows * q + rem.
Proof.
  induction rows as [| r rs IH]; intros q rem Hrem; simpl in *.
  - lia.
  - destruct rem as [| rem'].
    + simpl. rewrite IH by lia. lia.
    + simpl. rewrite IH by lia. lia.
Qed.

Theorem distribute_equal_sum : forall rows extra,
  rows <> [] ->
  sum_heights (distribute_equal rows extra) = sum_heights rows + extra.
Proof.
  intros rows extra Hne.
  unfold distribute_equal.
  destruct (length rows) eqn:E.
  - apply length_zero_iff_nil in E. contradiction.
  - rewrite <- E.
    assert (Hmod : extra mod length rows <= length