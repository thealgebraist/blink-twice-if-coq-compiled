### Audit Report: Agent 108 — Chromium Blink Table Cell Non-Overlap vs. CSS 2.1 §17.5

---

### 1. Table Grid Indexing and Layout Model

In CSS 2.1 §17.5 (Visual layout of table contents) and Chromium Blink's `TableLayoutAlgorithm` (`third_party/blink/renderer/core/layout/table/`), a table is structured into an orthogonal grid of rows and columns.

For the foundational non-spanning grid model (where `rowspan = 1` and `colspan = 1`):
* **Grid Coordinates:** Every table cell $C_{r, c}$ is uniquely indexed by a pair of natural numbers $(r, c) \in \mathbb{N} \times \mathbb{N}$, where $r$ is the `row_idx` and $c$ is the `col_idx`.
* **Column Offsets & Widths:** The layout engine computes a 1D horizontal track array. Each column $c$ is assigned a starting horizontal offset $X(c) \in \mathbb{Z}$ and a non-negative width $W_{\text{col}}(c) \ge 0$.
* **Row Offsets & Heights:** Similarly, each row $r$ is assigned a starting vertical offset $Y(r) \in \mathbb{Z}$ and a non-negative height $H_{\text{row}}(r) \ge 0$.
* **Cell Bounding Box:** A cell $C_{r, c}$ positioned at $(r, c)$ occupies a 2D closed bounding box $[x_1, x_1 + w_1] \times [y_1, y_1 + h_1]$ and an open interior rectangle:
  $$\text{Int}(C_{r, c}) = (x, x + w) \times (y, y + h)$$
  where $x = X(c)$, $y = Y(r)$, $w \le W_{\text{col}}(c)$, and $h \le H_{\text{row}}(r)$ (accounting for border-spacing or collapsed borders).

---

### 2. The Separation Invariant

To guarantee that table cells do not overlap visually (CSS 2.1 §17.5), Blink enforces monotonicity across row and column offsets:
* **Column Track Monotonicity:** $\forall c_1, c_2 \in \mathbb{N}, \quad c_1 < c_2 \implies X(c_1) + W_{\text{col}}(c_1) \le X(c_2)$
* **Row Track Monotonicity:** $\forall r_1, r_2 \in \mathbb{N}, \quad r_1 < r_2 \implies Y(r_1) + H_{\text{row}}(r_1) \le Y(r_2)$

Consequently, for any two distinct cells $C_1$ at $(r_1, c_1)$ with box $(x_1, y_1, w_1, h_1)$ and $C_2$ at $(r_2, c_2)$ with box $(x_2, y_2, w_2, h_2)$ where $(r_1, c_1) \neq (r_2, c_2)$:
1. **Row Separation ($r_1 \neq r_2$):** Either $r_1 < r_2 \implies y_1 + h_1 \le y_2$, or $r_2 < r_1 \implies y_2 + h_2 \le y_1$.
2. **Column Separation ($c_1 \neq c_2$):** Either $c_1 < c_2 \implies x_1 + w_1 \le x_2$, or $c_2 < c_1 \implies x_2 + w_2 \le x_1$.

---

### 3. Mathematical Proof of 2D Interior Disjointness

**Theorem:** Let $C_1$ and $C_2$ be two table cells in a valid table layout with grid indices $(r_1, c_1) \neq (r_2, c_2)$. Their interior rectangles $\text{Int}(C_1)$ and $\text{Int}(C_2)$ are strictly disjoint:
$$\text{Int}(C_1) \cap \text{Int}(C_2) = \emptyset$$

**Proof:**
1. By definition of the open interior of a 2D axis-aligned bounding box, a point $P = (p_x, p_y) \in \mathbb{Z}^2$ (or $\mathbb{R}^2$) belongs to $\text{Int}(C_i)$ if and only if:
   $$x_i < p_x < x_i + w_i \quad \land \quad y_i < p_y < y_i + h_i$$
2. Assume for the sake of contradiction that $\text{Int}(C_1) \cap \text{Int}(C_2) \neq \emptyset$. Then there exists at least one point $P = (p_x, p_y)$ such that $P \in \text{Int}(C_1)$ and $P \in \text{Int}(C_2)$. This yields four simultaneous strict inequalities:
   $$(1)\ x_1 < p_x < x_1 + w_1 \qquad (2)\ y_1 < p_y < y_1 + h_1$$
   $$(3)\ x_2 < p_x < x_2 + w_2 \qquad (4)\ y_2 < p_y < y_2 + h_2$$
3. Since $(r_1, c_1) \neq (r_2, c_2)$ and equality on natural numbers is decidable, it must hold that $r_1 \neq r_2 \lor c_1 \neq c_2$.
4. **Case 1: $r_1 \neq r_2$.** By the trichotomy of `<` on $\mathbb{N}$, either $r_1 < r_2$ or $r_2 < r_1$.
   * *Subcase 1a ($r_1 < r_2$):* By the Row Separation Invariant, $y_1 + h_1 \le y_2$. From $(2)$ we have $p_y < y_1 + h_1$, and from $(4)$ we have $y_2 < p_y$. Chaining these yields:
     $$p_y < y_1 + h_1 \le y_2 < p_y \implies p_y < p_y$$
     which is a contradiction.
   * *Subcase 1b ($r_2 < r_1$):* By the Row Separation Invariant, $y_2 + h_2 \le y_1$. Chaining with $(4)$ and $(2)$ yields:
     $$p_y < y_2 + h_2 \le y_1 < p_y \implies p_y < p_y$$
     which is a contradiction.
5. **Case 2: $c_1 \neq c_2$.** By trichotomy of `<` on $\mathbb{N}$, either $c_1 < c_2$ or $c_2 < c_1$.
   * *Subcase 2a ($c_1 < c_2$):* By the Column Separation Invariant, $x_1 + w_1 \le x_2$. Chaining with $(1)$ and $(3)$ yields:
     $$p_x < x_1 + w_1 \le x_2 < p_x \implies p_x < p_x$$
     which is a contradiction.
   * *Subcase 2b ($c_2 < c_1$):* By the Column Separation Invariant, $x_2 + w_2 \le x_1$. Chaining with $(3)$ and $(1)$ yields:
     $$p_x < x_2 + w_2 \le x_1 < p_x \implies p_x < p_x$$
     which is a contradiction.
6. In all possible cases, the assumption leads to a contradiction. Therefore, no such point $P$ exists, and $\text{Int}(C_1) \cap \text{Int}(C_2) = \emptyset$. $\blacksquare$

---

### 4. Formalization in Rocq / Coq (`BlinkTableCellNonOverlapSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization verifying both the general separation invariant and its concrete instantiation from Blink's 1D monotonic row/column track arrays.

```coq
(** * BlinkTableCellNonOverlapSemantics.v
    Formal Audit of Chromium Blink Table Cell Non-Overlap vs CSS 2.1 §17.5
    Agent 108 Verification Artifact *)

From Coq Require Import Arith ZArith Lia.
Open Scope Z_scope.

(** ** 1. Basic Geometric & Grid Definitions *)

Record GridPos := mkGridPos {
  row_idx : nat;
  col_idx : nat
}.

Record Rect := mkRect {
  x : Z;
  y : Z;
  w : Z;
  h : Z
}.

Record TableCell := mkCell {
  pos  : GridPos;
  bbox : Rect
}.

(** A point (px, py) lies strictly inside the open interior of a rectangle. *)
Definition in_interior (px py : Z) (r : Rect) : Prop :=
  r.(x) < px < r.(x) + r.(w) /\
  r.(y) < py < r.(y) + r.(h).

(** Two rectangles have disjoint interiors if no point lies in both. *)
Definition interior_disjoint (r1 r2 : Rect) : Prop :=
  forall px py : Z, ~ (in_interior px py r1 /\ in_interior px py r2).

(** ** 2. Separation Invariants *)

Definition row_separated (c1 c2 : TableCell) : Prop :=
  ( (c1.(pos).(row_idx) < c2.(pos).(row_idx))%nat /\
    c1.(bbox).(y) + c1.(bbox).(h) <= c2.(bbox).(y) )
  \/
  ( (c2.(pos).(row_idx) < c1.(pos).(row_idx))%nat /\
    c2.(bbox).(y) + c2.(bbox).(h) <= c1.(bbox).(y) ).

Definition col_separated (c1 c2 : TableCell) : Prop :=
  ( (c1.(pos).(col_idx) < c2.(pos).(col_idx))%nat /\
    c1.(bbox).(x) + c1.(bbox).(w) <= c2.(bbox).(x) )
  \/
  ( (c2.(pos).(col_idx) < c1.(pos).(col_idx))%nat /\
    c2.(bbox).(x) + c2.(bbox).(w) <= c1.(bbox).(x) ).

(** Inductive specification of the CSS 2.1 §17.5 / Blink Table Cell Invariant
    for any pair of cells with distinct grid coordinates. *)
Inductive ValidCellPair (c1 c2 : TableCell) : Prop :=
  | ValidPair_RowSep :
      row_separated c1 c2 -> ValidCellPair c1 c2
  | ValidPair_ColSep :
      col_separated c1 c2 -> ValidCellPair c1 c2.

(** Table-wide validity invariant over a predicate/set of cells. *)
Definition ValidTableGrid (InTable : TableCell -> Prop) : Prop :=
  forall c1 c2 : TableCell,
    InTable c1 ->
    InTable c2 ->
    c1.(pos) <> c2.(pos) ->
    ValidCellPair c1 c2.

(** ** 3. Concrete Blink Track-Based Layout Model *)

(** In Blink's TableLayoutAlgorithm, cell positions derive from 1D monotonic
    column and row offset arrays. *)
Record TrackLayout := mkTrackLayout {
  col_offset : nat -> Z;
  col_width  : nat -> Z;
  row_offset : nat -> Z;
  row_height : nat -> Z;

  col_monotonic : forall c1 c2 : nat,
    (c1 < c2)%nat -> col_offset c1 + col_width c1 <= col_offset c2;
  row_monotonic : forall r1 r2 : nat,
    (r1 < r2)%nat -> row_offset r1 + row_height r1 <= row_offset r2
}.

(** A cell conforms to a TrackLayout if its bounding box fits within its
    assigned (row_idx, col_idx) track slot. *)
Inductive CellFitsTrack (tl : TrackLayout) (c : TableCell) : Prop :=
  | mkCellFitsTrack :
      tl.(col_offset) c.(pos).(col_idx) <= c.(bbox).(x) ->
      c.(bbox).(x) + c.(bbox).(w) <=
        tl.(col_offset) c.(pos).(col_idx) + tl.(col_width) c.(pos).(col_idx) ->
      tl.(row_offset) c.(pos).(row_idx) <= c.(bbox).(y) ->
      c.(bbox).(y) + c.(bbox).(h) <=
        tl.(row_offset) c.(pos).(row_idx) + tl.(row_height) c.(pos).(row_idx) ->
      CellFitsTrack tl c.

(** ** 4. Helper Lemmas & Main Disjointness Theorems *)

Lemma grid_pos_neq_decomp : forall p1 p2 : GridPos,
  p1 <> p2 -> p1.(row_idx) <> p2.(row_idx) \/ p1.(col_idx) <> p2.(col_idx).
Proof.
  intros [r1 c1] [r2 c2] Hneq. simpl.
  destruct (Nat.eq_dec r1 r2) as [Hr | Hr];
  destruct (Nat.eq_dec c1 c2) as [Hc | Hc].
  - subst. exfalso. apply Hneq. reflexivity.
  - right. assumption.
  - left. assumption.
  - left. assumption.
Qed.

(** Theorem 1: Any pair of cells satisfying ValidCellPair has strictly
    disjoint 2D interior rectangles. *)
Theorem valid_cell_pair_disjoint : forall c1 c2 : TableCell,
  ValidCellPair c1 c2 ->
  interior_disjoint c1.(bbox) c2.(bbox).
Proof.
  intros c1 c2 Hvalid px py [Hin1 Hin2].
  unfold in_interior in Hin1, Hin2.
  destruct Hvalid as [Hrow | Hcol].
  - (* Case 1: Row separation *)
    destruct Hrow as [[_ Hsep] | [_ Hsep]]; lia.
  - (* Case 2: Column separation *)
    destruct Hcol as [[_ Hsep] | [_ Hsep]]; lia.
Qed.

(** Theorem 2: Global non-overlap across any ValidTableGrid. *)
Theorem blink_table_cell_non_overlap :
  forall (InTable : TableCell -> Prop),
    ValidTableGrid InTable ->
    forall c1 c2 : TableCell,
      InTable c1 ->
      InTable c2 ->