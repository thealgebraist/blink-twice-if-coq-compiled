### 1. GridPlacement Cursor Management in Chromium Blink vs. CSS Grid 1 §8.5

In Chromium Blink (`third_party/blink/renderer/core/layout/grid/grid_placement.cc` / `GridPlacement::RunAutoPlacementAlgorithm`), the auto-placement cursor $(r_{cursor}, c_{cursor})$ tracks the starting grid track coordinates for searching the next available space for an auto-placed grid item. 

Under CSS Grid Layout Module Level 1 §8.5 ( Grid Item Placement Algorithm), Step 4 governs the placement of remaining auto-placed items (items without a definite row or column position):

*   **Sparse Packing (`row` / `column` without `dense`):**
    The auto-placement cursor is initialized to $(0, 0)$ prior to processing the auto-placed items. For each item:
    1. If the item has a definite position in the minor axis (e.g., definite column when flow is `row`), the cursor's minor-axis coordinate is set to that definite start index. If this index is less than the cursor's previous minor-axis coordinate, the major-axis coordinate (row) is incremented by 1.
    2. The algorithm increments the cursor's minor-axis coordinate (wrapping to the next major-axis track and resetting the minor-axis to $0$ when the minor-axis span exceeds the explicit/implicit grid bounds) until it locates a contiguous $span_{row} \times span_{col}$ region that does not intersect any previously occupied cells.
    3. Once the item is placed at $(r_{item}, c_{item})$, the cursor's position is updated to $(r_{item}, c_{item})$. Thus, the cursor advances **monotonically** in lexicographical order $(r, c)$ across the item sequence.

*   **Dense Packing (`row dense` / `column dense`):**
    Blink sets the boolean flag `is_dense_packing_` based on `ComputedStyle::IsGridAutoFlowAlgorithmDense()`. During the auto-placement loop:
    1. **Cursor Reset:** Before searching for a placement position for *each* unplaced item, the auto-placement cursor is reset to the start of the grid: $(0, 0)$.
    2. If the item has a definite minor-axis position $c_{def}$, the cursor is initialized to $(0, c_{def})$ (assuming `row dense` flow).
    3. The search proceeds in lexicographical order from $(0, 0)$ (or $(0, c_{def})$) until the first unoccupied region matching the item's spans $(span_r, span_c)$ is found.
    4. Because the cursor resets on every iteration, an item with a smaller span can backtrack into "holes" skipped over by earlier, larger items.

---

### 2. Core Algorithmic Invariants

Let the grid have a fixed minor-axis dimension $W > 0$ (number of columns in `row` flow) and an unbounded major-axis dimension $\mathbb{N}$. Each placed item $i$ occupies a discrete 2D half-open interval $[r_i, r_i + h_i) \times [c_i, c_i + w_i)$, where $w_i \le W$.

1.  **Mutual Disjointness (No-Overlap Invariant):**
    For any two distinct placed items $i \neq j$, their occupied cell regions are strictly disjoint:
    $$\forall (r, c), \quad \neg \big( (r_i \le r < r_i + h_i \land c_i \le c < c_i + w_i) \land (r_j \le r < r_j + h_j \land c_j \le c < c_j + w_j) \big)$$
2.  **Grid Bounds Confinement:**
    Every placed item fits completely within the minor-axis track count $W$:
    $$\forall i, \quad c_i + w_i \le W$$
3.  **Sparse Monotonicity Invariant:**
    In non-dense mode, for a sequence of auto-placed items without definite coordinates $i_1, i_2, \dots, i_k$, their assigned top-left anchors $(r_{i_m}, c_{i_m})$ satisfy:
    $$r_{i_m} < r_{i_{m+1}} \lor (r_{i_m} = r_{i_{m+1}} \land c_{i_m} < c_{i_{m+1}})$$
4.  **Dense No-Fillable-Holes Invariant (Optimality):**
    In `dense` mode, when an item $i$ with dimensions $(h_i, w_i)$ is placed at $(r_i, c_i)$, there exists no valid placement anchor $(r', c')$ strictly preceding $(r_i, c_i)$ in lexicographical order that was unoccupied at the moment item $i$ was placed:
    $$\forall (r', c') \prec_{lex} (r_i, c_i), \quad c' + w_i \le W \implies \exists (r, c) \in [r', r'+h_i) \times [c', c'+w_i) \text{ occupied prior to } i.$$

---

### 3. Rocq / Coq Formalization: `BlinkGridDensePlacementSemantics.v`

The following self-contained Rocq (Coq) development formalizes the Blink grid occupancy state, cursor progression, sparse vs. dense placement algorithms, and proves the Disjointness and No-Fillable-Holes invariants.

```coq
(** * BlinkGridDensePlacementSemantics.v
    Formal Audit of Chromium Blink Grid Auto-Placement (Dense vs Sparse)
    against CSS Grid Layout Module Level 1 §8.5. *)

From Coq Require Import Arith PeanoNat Bool List Lia.
Import ListNotations.

(** ** 1. Grid Geometry and Primitives *)

Record Coord := mkCoord {
  row : nat;
  col : nat
}.

Record ItemSpec := mkItem {
  id     : nat;
  span_r : nat;
  span_c : nat
}.

Record PlacedItem := mkPlaced {
  p_item : ItemSpec;
  p_pos  : Coord
}.

(** Lexicographical ordering on coordinates (Row-major order). *)
Definition coord_lt (a b : Coord) : Prop :=
  row a < row b \/ (row a = row b /\ col a < col b).

Definition coord_le (a b : Coord) : Prop :=
  coord_lt a b \/ a = b.

(** Does a placed item cover a specific grid cell (r, c)? *)
Definition covers_cell (p : PlacedItem) (r c : nat) : bool :=
  let r0 := row (p_pos p) in
  let c0 := col (p_pos p) in
  let hr := span_r (p_item p) in
  let wc := span_c (p_item p) in
  (r0 <=? r) && (r <? r0 + hr) && (c0 <=? c) && (c <? c0 + wc).

(** Is a cell (r, c) occupied by any item in the current grid state? *)
Definition cell_occupied (state : list PlacedItem) (r c : nat) : bool :=
  existsb (fun p => covers_cell p r c) state.

(** Check if a rectangular region [r0, r0 + hr) x [c0, c0 + wc) is completely free. *)
Fixpoint range_free_cols (state : list PlacedItem) (r c0 count : nat) : bool :=
  match count with
  | 0 => true
  | S count' => negb (cell_occupied state r c0) && range_free_cols state r (S c0) count'
  end.

Fixpoint region_free (state : list PlacedItem) (r0 c0 hr wc : nat) : bool :=
  match hr with
  | 0 => true
  | S hr' => range_free_cols state r0 c0 wc && region_free state (S r0) c0 hr' wc
  end.

(** Valid placement check at candidate coordinate `pos` within grid width `W`. *)
Definition can_place_at (W : nat) (state : list PlacedItem) (it : ItemSpec) (pos : Coord) : bool :=
  (col pos + span_c it <=? W) &&
  region_free state (row pos) (col pos) (span_r it) (span_c it).

(** ** 2. Cursor Advancement and Search *)

(** Advance cursor by one step in row-major order for a grid of width W. *)
Definition step_cursor (W : nat) (cur : Coord) : Coord :=
  if S (col cur) <? W then
    mkCoord (row cur) (S (col cur))
  else
    mkCoord (S (row cur)) 0.

(** Bounded search for the next valid placement position starting from `cur`.
    In Blink, the implicit grid can grow up to a finite bound per item. *)
Fixpoint find_position (W : nat) (state : list PlacedItem) (it : ItemSpec)
                       (cur : Coord) (fuel : nat) : option Coord :=
  match fuel with
  | 0 => None
  | S fuel' =>
      if can_place_at W state it cur then
        Some cur
      else
        find_position W state it (step_cursor W cur) fuel'
  end.

(** ** 3. Sparse vs. Dense Placement Algorithms *)

(** Place a single item in Sparse mode: starts at `cur`, updates cursor to placed pos. *)
Definition place_one_sparse (W fuel : nat) (state : list PlacedItem) (cur : Coord) (it : ItemSpec)
  : (list PlacedItem * Coord) :=
  match find_position W state it cur fuel with
  | Some pos => (mkPlaced it pos :: state, pos)
  | None     => (state, cur)
  end.

(** Place a single item in Dense mode: resets search to (0, 0) for every item. *)
Definition place_one_dense (W fuel : nat) (state : list PlacedItem) (it : ItemSpec)
  : list PlacedItem :=
  match find_position W state it (mkCoord 0 0) fuel with
  | Some pos => mkPlaced it pos :: state
  | None     => state
  end.

Fixpoint place_all_sparse (W fuel : nat) (state : list PlacedItem) (cur : Coord) (items : list ItemSpec)
  : (list PlacedItem * Coord) :=
  match items with
  | [] => (state, cur)
  | it :: rest =>
      let (state', cur') := place_one_sparse W fuel state cur it in
      place_all_sparse W fuel state' cur' rest
  end.

Fixpoint place_all_dense (W fuel : nat) (state : list PlacedItem) (items : list ItemSpec)
  : list PlacedItem :=
  match items with
  | [] => state
  | it :: rest =>
      let state' := place_one_dense W fuel state it in
      place_all_dense W fuel state' rest
  end.

(** ** 4. Lemmas for Region Occupancy and Disjointness *)

Lemma range_free_cols_spec : forall state r c0 wc c,
  range_free_cols state r c0 wc = true ->
  c0 <= c < c0 + wc ->
  cell_occupied state r c = false.
Proof.
  intros state r c0 wc. revert c0.
  induction wc as [|wc' IH]; intros c0 c Hfree Hbounds.
  - lia.
  - simpl in Hfree. apply andb_prop in Hfree. destruct Hfree as [Hhead Htail].
    destruct (Nat.eq_dec c c0) as [Heq | Hneq].
    + subst. apply negb_true_iff in Hhead. exact Hhead.
    + apply IH with (c0 := S c0); [exact Htail | lia].
Qed.

Lemma region_free_spec : forall state r0 c0 hr wc r c,
  region_free state r0 c0 hr wc = true ->
  r0 <= r < r0 + hr ->
  c0 <= c < c0 + wc ->
  cell_occupied state r c = false.
Proof.
  intros state r0 c0 hr wc. revert r0.
  induction hr as [|hr' IH]; intros r0 r c Hfree Hr Hc.
  - lia.
  - simpl in Hfree. apply andb_prop in Hfree. destruct Hfree as [Hrow Hrest].
    destruct (Nat.eq_dec r r0) as [Heq | Hneq].
    + subst. eapply range_free_cols_spec; eauto.
    + eapply IH with (r0 := S r0); [exact Hrest | lia | exact Hc].
Qed.

Lemma covers_cell_bounds : forall p r c,
  covers_cell p r c = true ->
  row (p_pos p) <= r < row (p_pos p) + span_r (p_item p) /\
  col (p_pos p) <= c < col (p_pos p) + span_c (p_item p).
Proof.
  intros p r c Hcov.
  unfold covers_cell in Hcov.
  repeat (apply andb_prop in Hcov; destruct Hcov as [Hcov ?]).
  apply Nat.leb_le in Hcov.
  apply Nat.ltb_lt in H1.
  apply Nat.leb_le in H0.
  apply Nat.ltb_lt in H.
  lia.
Qed.

Lemma find_position_valid : forall W state it cur fuel pos,
  find_position W state it cur fuel = Some pos ->
  can_place_at W state it pos = true.
Proof.
  intros W state it cur fuel. revert cur.
  induction fuel as [|fuel' IH]; intros cur pos Hfind; simpl in Hfind.
  - discriminate.
  - destruct (can_place_at W state it cur) eqn:Hcan.
    + injection Hfind as Heq. subst. exact Hcan.
    + apply IH in Hfind. exact Hfind.
Qed.

(** ** 5. Invariant 1: Mutual Disjointness (Non-Overlapping Items) *)

Definition mutually_disjoint (state : list PlacedItem) : Prop :=
  forall p1 p2 r c,
    In p1 state ->
    In p2 state ->
    p1 <> p2 ->
     ~(covers_cell p1 r c = true /\ covers_cell p2 r c = true).

(** A newly placed item does not overlap with any existing item in `state`. *)
Lemma new_placement_disjoint_from_existing : forall W state it pos p r c,
  can_place_at W state it pos = true ->
  In p state ->
  covers_cell (mkPlaced it pos) r c = true ->
  covers_cell p r c = false.
Proof.
  intros W state it pos