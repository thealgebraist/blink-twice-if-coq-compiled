### 1. Representation & Clamping Bounds (HTML §4.9.11 / Blink)

In the HTML Living Standard (§4.9.11, *Attributes common to td and th elements*), `colspan` is clamped to $[1, 1000]$ and `rowspan` to $[0, 65534]$ (where $0$ spans to the end of the row group). However, inside Chromium Blink’s layout engine (`third_party/blink/renderer/core/layout/table/`), layout-level representation (`LayoutTableCell` / `NGTableNode`) normalizes and clamps both effective spans to bounded positive integers:
$$\text{colspan}, \text{rowspan} \in [1, 65534] \quad (\text{where } \text{kMaxTableSpan} = 65534, \text{kMinTableSpan} = 1)$$

A cell positioned at grid origin $(r_0, c_0)$ with clamped spans $(s_r, s_c)$ occupies the discrete 2D half-open bounding box:
$$\mathcal{B}(r_0, c_0, s_r, s_c) = [r_0, r_0 + s_r) \times [c_0, c_0 + s_c)$$

---

### 2. Spanned Width & Height Accumulation (CSS 2.1 §17.5.1)

Under the separated borders model (`border-collapse: separate`), CSS 2.1 §17.5.1 dictates that a cell spanning $k$ columns or rows absorbs the widths/heights of all spanned tracks plus the internal `border-spacing` gaps between adjacent spanned tracks.

Let $W: \mathbb{N} \to \mathbb{N}$ be the resolved column width vector, $H: \mathbb{N} \to \mathbb{N}$ be the resolved row height vector, and $b_h, b_v \ge 0$ be the horizontal and vertical border spacings. For a cell at $(r_0, c_0)$ with effective spans $(s_r, s_c)$:

$$\text{CellWidth}(c_0, s_c, b_h) = \left( \sum_{i = c_0}^{c_0 + s_c - 1} W(i) \right) + (s_c - 1) \cdot b_h$$

$$\text{CellHeight}(r_0, s_r, b_v) = \left( \sum_{j = r_0}^{r_0 + s_r - 1} H(j) \right) + (s_r - 1) \cdot b_v$$

*(In the collapsed borders model, $b_h = b_v = 0$.)*

---

### 3. Core Layout Invariants

1. **Clamping Validity:** For any raw input span $n \in \mathbb{N}$, $1 \le \text{clamp\_span}(n) \le 65534$.
2. **Track Monotonicity (Span Width $\ge$ Individual Track Width):** Because track sizes and border spacings are non-negative (in `LayoutUnit` / pixel space), for any column $c \in [c_0, c_0 + s_c)$, $\text{CellWidth}(c_0, s_c, b_h) \ge W(c)$.
3. **Grid Slot Disjointness:** Two cells with non-overlapping 1D projections on either the row axis or the column axis occupy strictly disjoint sets of $(r, c)$ grid slots.

---

### 4. Formal Verification in Rocq / Coq (`BlinkTableColspanRowspanSemantics.v`)

```coq
(** * BlinkTableColspanRowspanSemantics.v
    Formal audit of Chromium Blink Colspan/Rowspan expansion against
    HTML §4.9.11 and CSS 2.1 §17.5.1 by Agent 114. *)

From Coq Require Import Arith PeanoNat Lia List.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Constants and Clamping (HTML §4.9.11 & Blink Limits) *)

Definition kMinSpan : nat := 1.
Definition kMaxSpan : nat := 65534.

Definition clamp_span (raw_span : nat) : nat :=
  Nat.min (Nat.max raw_span kMinSpan) kMaxSpan.

Lemma clamp_span_bounds : forall n : nat,
  kMinSpan <= clamp_span n <= kMaxSpan.
Proof.
  intros n. unfold clamp_span, kMinSpan, kMaxSpan.
  lia.
Qed.

(** ** 2. Cell Grid Representation *)

Record TableCell := mkCell {
  row_start : nat;
  col_start : nat;
  raw_rowspan : nat;
  raw_colspan : nat
}.

Definition eff_rowspan (c : TableCell) : nat := clamp_span (raw_rowspan c).
Definition eff_colspan (c : TableCell) : nat := clamp_span (raw_colspan c).

Definition row_end (c : TableCell) : nat := row_start c + eff_rowspan c.
Definition col_end (c : TableCell) : nat := col_start c + eff_colspan c.

(** A grid coordinate (r, col) is occupied by cell [c] *)
Definition occupies_slot (c : TableCell) (r col : nat) : Prop :=
  row_start c <= r < row_end c /\
  col_start c <= col < col_end c.

(** ** 3. Spanned Width and Height Accumulation (CSS 2.1 §17.5.1) *)

(** Sum of [count] tracks starting at index [start] given track metric [f] *)
Fixpoint sum_tracks (f : nat -> nat) (start count : nat) : nat :=
  match count with
  | 0 => 0
  | S count' => f start + sum_tracks f (S start) count'
  end.

(** Accumulated spanned dimension: sum of track sizes + (span - 1) * border_spacing *)
Definition accumulate_span_size (track_size : nat -> nat) (start span spacing : nat) : nat :=
  sum_tracks track_size start span + (span - 1) * spacing.

Definition cell_spanned_width (col_widths : nat -> nat) (border_spacing_h : nat) (c : TableCell) : nat :=
  accumulate_span_size col_widths (col_start c) (eff_colspan c) border_spacing_h.

Definition cell_spanned_height (row_heights : nat -> nat) (border_spacing_v : nat) (c : TableCell) : nat :=
  accumulate_span_size row_heights (row_start c) (eff_rowspan c) border_spacing_v.

(** ** 4. Proofs of Layout Invariants *)

(** Helper lemma: any individual track within the spanned range is bounded by [sum_tracks] *)
Lemma sum_tracks_ge_individual : forall (f : nat -> nat) (start count idx : nat),
  start <= idx < start + count ->
  f idx <= sum_tracks f start count.
Proof.
  intros f start count. revert start.
  induction count as [| count' IH]; intros start idx Hbound.
  - lia.
  - simpl. destruct (Nat.eq_dec idx start) as [Heq | Hneq].
    + subst. lia.
    + assert (Hbound' : S start <= idx < S start + count') by lia.
      specialize (IH (S start) idx Hbound').
      lia.
Qed.

(** Invariant 1: Spanned width is >= any individual spanned column's width *)
Theorem spanned_width_ge_col_width :
  forall (col_widths : nat -> nat) (spacing : nat) (c : TableCell) (col : nat),
    col_start c <= col < col_end c ->
    col_widths col <= cell_spanned_width col_widths spacing c.
Proof.
  intros col_widths spacing c col Hcol.
  unfold cell_spanned_width, accumulate_span_size, col_end in *.
  pose proof (sum_tracks_ge_individual col_widths (col_start c) (eff_colspan c) col Hcol) as Hsum.
  lia.
Qed.

(** Invariant 2: Spanned height is >= any individual spanned row's height *)
Theorem spanned_height_ge_row_height :
  forall (row_heights : nat -> nat) (spacing : nat) (c : TableCell) (r : nat),
    row_start c <= r < row_end c ->
    row_heights r <= cell_spanned_height row_heights spacing c.
Proof.
  intros row_heights spacing c r Hrow.
  unfold cell_spanned_height, accumulate_span_size, row_end in *.
  pose proof (sum_tracks_ge_individual row_heights (row_start c) (eff_rowspan c) r Hrow) as Hsum.
  lia.
Qed.

(** Definition of non-overlapping cells in 2D table grid *)
Definition cells_non_overlapping (c1 c2 : TableCell) : Prop :=
  col_end c1 <= col_start c2 \/
  col_end c2 <= col_start c1 \/
  row_end c1 <= row_start c2 \/
  row_end c2 <= row_start c1.

(** Invariant 3: Non-overlapping multi-span cells occupy strictly disjoint grid slots *)
Theorem non_overlapping_cells_disjoint :
  forall (c1 c2 : TableCell) (r col : nat),
    cells_non_overlapping c1 c2 ->
    occupies_slot c1 r col ->
    occupies_slot c2 r col ->
    False.
Proof.
  intros c1 c2 r col Hnon [Hr1 Hc1] [Hr2 Hc2].
  unfold cells_non_overlapping in Hnon.
  lia.
Qed.

(** Invariant 4: A single-span cell (span = 1) adds zero border-spacing overhead *)
Theorem single_span_zero_spacing :
  forall (track_size : nat -> nat) (start spacing : nat),
    accumulate_span_size track_size start 1 spacing = track_size start.
Proof.
  intros track_size start spacing.
  unfold accumulate_span_size. simpl. lia.
Qed.
```