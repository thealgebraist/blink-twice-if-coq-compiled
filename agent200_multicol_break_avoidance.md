### 1. Audit Analysis: Chromium Blink Column Break Avoidance vs. CSS Fragmentation 3 §3

In Chromium Blink’s LayoutNG fragmentation engine (`NGColumnLayoutAlgorithm` and `NGFragmentationUtils`), break avoidance for monolithic or `break-inside: avoid` blocks is governed by evaluating the remaining space in the current fragmentainer (column) against the block's unbreakable block-size.

According to **CSS Fragmentation Module Level 3 §3 (Breaking Controls)**:
* When an unbreakable block (or a block with `break-inside: avoid`) of height $h$ is encountered at block-offset $y$ within a column of total height $H_{\text{col}}$, the remaining fragmentainer space is $R = H_{\text{col}} - y$.
* **Condition ($h > R$):** If the block cannot fit in the remaining space ($y + h > H_{\text{col}}$) and is not already at the top of the column ($y > 0$, preventing infinite column progression), Blink pushes the block to the next column.
* **State Transition:** The block is placed at the top of the subsequent fragmentainer, setting its new block-offset to $y_{\text{new}} = 0$ and incrementing the column index $\text{col\_idx}_{\text{new}} = \text{col\_idx} + 1$.

---

### 2. Core Invariants

1. **Strict Column Progression (Monotonicity):** When a break avoidance push occurs (given $y > 0$ and $y + h > H_{\text{col}}$), the column index strictly increases ($\text{col\_idx}_{\text{new}} > \text{col\_idx}$), and the block is anchored to the fragmentainer start ($y_{\text{new}} = 0$).
2. **Next-Column Containment (No-Overflow Guarantee):** If the block's height is bounded by the fragmentainer capacity ($h \le H_{\text{col}}$), shifting the block to the next column guarantees that it fits entirely within that new column without overflowing ($y_{\text{new}} + h \le H_{\text{col}}$).

---

### 3. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkMulticolBreakAvoidanceSemantics.v`, compatible with Coq 8.16+ / Rocq 9.0.

```coq
(** * BlinkMulticolBreakAvoidanceSemantics.v
    Formal Audit of Chromium Blink Column Break Avoidance vs. CSS Fragmentation 3 §3
    Agent 200 *)

From Coq Require Import Arith PeanoNat Lia Bool.

Module BlinkMulticolBreakAvoidance.

  (** ** State and Geometry Definitions *)

  (** Represents the layout cursor position within a multi-column container. *)
  Record LayoutPosition := mkPos {
    col_idx : nat;
    y_offset : nat
  }.

  (** Parameters for placing an unbreakable (or break-inside: avoid) block:
      - [col_h]: Total block-size (height) of a column fragmentainer.
      - [h]: Block-size (height) of the child block being placed.
      - [pos]: Current layout position (column index and block-offset). *)
  Definition place_unbreakable_block (col_h h : nat) (pos : LayoutPosition) : LayoutPosition :=
    let y := y_offset pos in
    let c := col_idx pos in
    (* If we are not at the top of the column (y > 0) and the block overflows 
       the remaining space (h > col_h - y, expressed safely in nat as y + h > col_h),
       push to the top of the next column. *)
    if (0 <? y) && (col_h <? y + h) then
      mkPos (c + 1) 0
    else
      pos.

  (** Predicate stating that a block of height [h] placed at [pos] fits within 
      the column of height [col_h]. *)
  Definition fits_in_column (col_h h : nat) (pos : LayoutPosition) : Prop :=
    y_offset pos + h <= col_h.

  (** ** Verification Theorems & Invariants *)

  (** Theorem 1: When block height exceeds remaining column space (and y > 0),
      the block is moved to the top of the next column (y_new = 0, col_idx + 1). *)
  Theorem break_avoidance_pushes_to_next_col :
    forall (col_h h : nat) (pos : LayoutPosition),
      y_offset pos > 0 ->
      y_offset pos + h > col_h ->
      let pos' := place_unbreakable_block col_h h pos in
      col_idx pos' = col_idx pos + 1 /\ y_offset pos' = 0.
  Proof.
    intros col_h h [c y] Hy Hoverflow.
    unfold place_unbreakable_block. simpl in *.
    assert (H1 : (0 <? y) = true) by (apply Nat.ltb_lt; lia).
    assert (H2 : (col_h <? y + h) = true) by (apply Nat.ltb_lt; lia).
    rewrite H1, H2. simpl.
    split; reflexivity.
  Qed.

  (** Theorem 2 (Invariant 1): Column index strictly increases upon a break push. *)
  Theorem column_index_strictly_increases_on_push :
    forall (col_h h : nat) (pos : LayoutPosition),
      y_offset pos > 0 ->
      y_offset pos + h > col_h ->
      col_idx pos < col_idx (place_unbreakable_block col_h h pos).
  Proof.
    intros col_h h pos Hy Hoverflow.
    pose proof (break_avoidance_pushes_to_next_col col_h h pos Hy Hoverflow) as [Hcol _].
    lia.
  Qed.

  (** Theorem 3 (Invariant 2): If the block height is at most the column height (h <= col_h),
      the placed block is guaranteed to fit entirely within its resulting column. *)
  Theorem block_fits_entirely_if_bounded_by_col_height :
    forall (col_h h : nat) (pos : LayoutPosition),
      h <= col_h ->
      fits_in_column col_h h (place_unbreakable_block col_h h pos).
  Proof.
    intros col_h h [c y] Hbound.
    unfold place_unbreakable_block, fits_in_column. simpl.
    destruct (0 <? y) eqn:Hy; destruct (col_h <? y + h) eqn:Hov; simpl.
    - (* Case: y > 0 and y + h > col_h (Pushed to next column) *)
      lia.
    - (* Case: y > 0 and y + h <= col_h (Fits in current column) *)
      apply Nat.ltb_ge in Hov. lia.
    - (* Case: y = 0 and y + h > col_h (Contradicts h <= col_h) *)
      apply Nat.ltb_ge in Hy.
      apply Nat.ltb_lt in Hov.
      lia.
    - (* Case: y = 0 and y + h <= col_h (Fits at top of current column) *)
      apply Nat.ltb_ge in Hov. lia.
  Qed.

  (** Theorem 4 (Monotonicity Invariant): Across all possible inputs, placement 
      never moves the layout position backward in column index. *)
  Theorem placement_column_monotonic :
    forall (col_h h : nat) (pos : LayoutPosition),
      col_idx pos <= col_idx (place_unbreakable_block col_h h pos).
  Proof.
    intros col_h h [c y].
    unfold place_unbreakable_block. simpl.
    destruct ((0 <? y) && (col_h <? y + h)); simpl; lia.
  Qed.

End BlinkMulticolBreakAvoidance.
```