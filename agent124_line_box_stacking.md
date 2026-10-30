### 1. Accumulation of Multiple Line Boxes Within a Block Container

According to CSS 2.1 §10.8 (Line height calculations) and CSS Inline Layout Module Level 3 §3 (Line Boxes), inline-level content within an inline formatting context is laid out sequentially into a vertical stack of rectangular areas called *line boxes*. 

In Chromium Blink's LayoutNG architecture (specifically within `InlineLayoutAlgorithm` and `FragmentBuilder`), when a block container establishes an inline formatting context and contains no intersecting floats or forced clearance between lines, line boxes are stacked contiguously along the block-progression direction (the vertical axis in horizontal writing modes).

Let a block container generate a finite sequence of $n$ line boxes, indexed $k \in \{0, 1, \dots, n-1\}$. Each line box $k$ has a computed logical height $h_k \ge 0$, determined by the distance between the highest ascent (or top of aligned `top` boxes) and lowest descent (or bottom of aligned `bottom` boxes) of all inline-level boxes participating in that line box.

The total intrinsic block-size (content height) contributed by the line boxes to the parent block container is the exact arithmetic sum of the individual line box heights:

$$\text{total\_height} = \sum_{k=0}^{n-1} h_k$$

In Blink, this accumulation is tracked via an internal cursor (`intrinsic_block_size_`). As each line box fragment is constructed by `InlineLayoutAlgorithm::CreateLine`, its logical height is added directly to the container's running block-size total.

---

### 2. Line Box Offset Progression

Line boxes are positioned within the block container's coordinate space starting at an initial block-start offset $y_0$ (typically $y_0 = 0$ relative to the container's content box, or equal to the block-start border and padding offset if measured in the border-box coordinate space).

CSS 2.1 §9.4.2 specifies that line boxes are stacked with no vertical separation (they never collapse margins, as line boxes do not have margins) and they never overlap under standard non-negative line height conditions. Consequently, the block-offset $y_{k+1}$ of the $(k+1)$-th line box is strictly determined by the recurrence relation:

$$y_{k+1} = y_k + h_k \quad \text{for } 0 \le k < n$$

Expanding this recurrence yields the closed-form offset for any line box $k$:

$$y_k = y_0 + \sum_{i=0}^{k-1} h_i$$

And the final cursor position after placing all $n$ line boxes is:

$$y_n = y_0 + \text{total\_height}$$

In Blink's `LineBoxFragmentBuilder`, the `BfcOffset` or relative logical offset of the newly generated `PhysicalLineBoxFragment` is assigned the current running block offset $y_k$, and the layout opportunity / block offset cursor is immediately advanced by $h_k$ to prepare for line $k+1$.

---

### 3. Formal Invariants

Under the standard physical layout constraint of CSS 2.1 §10.8 that line box heights cannot be negative ($\forall k, h_k \ge 0$), Blink's line box stacking upholds three fundamental geometric invariants:

1. **Line Box Index Monotonicity (Offset Monotonicity):**
   As the line box index increases, the vertical start offset of the line box is monotonically non-decreasing:
   $$\forall i, j \in \{0, \dots, n-1\}, \quad i \le j \implies y_i \le y_j$$
   *Audit Note:* If a line is completely empty or contains only zero-height inline elements, $h_i = 0$, resulting in $y_{i+1} = y_i$. Otherwise, for $h_i > 0$, offset progression is strictly increasing ($y_i < y_{i+1}$).

2. **Non-Overlapping Vertical Line Boxes:**
   Each line box $k$ occupies the half-open vertical interval $I_k = [y_k, y_k + h_k)$. Because $y_{k+1} = y_k + h_k$ and $h_k \ge 0$, the end of line box $k$ coincides exactly with the start of line box $k+1$. For any two distinct line boxes $i < j$:
   $$y_i + h_i = y_{i+1} \le y_j$$
   Thus, the interior vertical intervals of any two line boxes are disjoint:
   $$\forall i \neq j, \quad [y_i, y_i + h_i) \cap [y_j, y_j + h_j) = \emptyset$$

3. **Total Height Non-Negativity:**
   Since the base step of an empty container has $\text{total\_height} = 0$, and every accumulated line height satisfies $h_k \ge 0$, the total accumulated height of the line box stack is guaranteed to be non-negative:
   $$\text{total\_height} = \sum_{k=0}^{n-1} h_k \ge 0$$

---

### 4. Concrete Rocq/Coq Definitions and Theorems (`BlinkLineBoxStackingSemantics.v`)

The following self-contained Rocq (Coq) specification formalizes Blink's fixed-point `LayoutUnit` (modeled in $\mathbb{Z}$) line box stacking semantics, proving the equivalence of iterative cursor accumulation and functional summation, as well as the three core invariants.

```coq
(** * BlinkLineBoxStackingSemantics.v
    Formal audit of Chromium Blink Line Box Stacking against
    CSS Inline Layout Module Level 3 §3 and CSS 2.1 §10.8. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Layout Primitives *)

(** In Blink, LayoutUnit is a fixed-point arithmetic type. We model it as Z. *)
Definition LayoutUnit := Z.

(** Input specification for an unplaced line box computed by InlineLayoutAlgorithm. *)
Record UnplacedLineBox := mkUnplacedLine {
  ul_height : LayoutUnit
}.

(** A placed PhysicalLineBoxFragment within a block container's fragment builder. *)
Record PlacedLineBox := mkPlacedLine {
  pl_index  : nat;
  pl_offset : LayoutUnit; (* y_k *)
  pl_height : LayoutUnit  (* h_k *)
}.

(** Well-formedness condition: CSS 2.1 §10.8 requires line box heights to be non-negative. *)
Definition valid_line_height (u : UnplacedLineBox) : Prop :=
  0 <= ul_height u.

Definition valid_line_list (lines : list UnplacedLineBox) : Prop :=
  Forall valid_line_height lines.

(** ** 2. Functional Specification (CSS 2.1 §10.8 & Inline 3 §3) *)

(** Total height is the sum of all line box heights: total_height = sum line_heights. *)
Fixpoint sum_line_heights (lines : list UnplacedLineBox) : LayoutUnit :=
  match lines with
  | [] => 0
  | l :: rest => ul_height l + sum_line_heights rest
  end.

(** ** 3. Blink Operational Semantics (Iterative Cursor Progression) *)

(** Models Blink's InlineLayoutAlgorithm placing lines sequentially by advancing
    the block-offset cursor: y_{k+1} = y_k + h_k. *)
Fixpoint stack_lines_aux
  (lines : list UnplacedLineBox)
  (curr_idx : nat)
  (curr_y : LayoutUnit) : list PlacedLineBox * LayoutUnit :=
  match lines with
  | [] => ([], curr_y)
  | l :: rest =>
      let h := ul_height l in
      let placed := mkPlacedLine curr_idx curr_y h in
      let (placed_rest, final_y) := stack_lines_aux rest (S curr_idx) (curr_y + h) in
      (placed :: placed_rest, final_y)
  end.

(** Top-level stacking function starting at initial block offset y_0. *)
Definition stack_lines (lines : list UnplacedLineBox) (y0 : LayoutUnit)
  : list PlacedLineBox * LayoutUnit :=
  stack_lines_aux lines 0%nat y0.

(** Helper to extract the list of placed boxes. *)
Definition placed_boxes (lines : list UnplacedLineBox) (y0 : LayoutUnit) : list PlacedLineBox :=
  fst (stack_lines lines y0).

(** Helper to extract the final cursor position y_n. *)
Definition final_offset (lines : list UnplacedLineBox) (y0 : LayoutUnit) : LayoutUnit :=
  snd (stack_lines lines y0).

(** ** 4. Structural Lemmas *)

Lemma stack_lines_aux_length : forall lines idx y,
  length (fst (stack_lines_aux lines idx y)) = length lines.
Proof.
  induction lines as [| l rest IH]; intros idx y; simpl.
  - reflexivity.
  - destruct (stack_lines_aux rest (S idx) (y + ul_height l)) as [placed_rest final_y] eqn:E.
    simpl. f_equal.
     specialize (IH (S idx) (y + ul_height l)).
    rewrite E in IH. exact IH.
Qed.

(** ** 5. Proof of Requirement 1: Total Height Accumulation *)

Theorem blink_cursor_accumulation_correct : forall lines idx y0,
  snd (stack_lines_aux lines idx y0) = y0 + sum_line_heights lines.
Proof.
  induction lines as [| l rest IH]; intros idx y0; simpl.
  - lia.
  - destruct (stack_lines_aux rest (S idx) (y0 + ul_height l)) as [placed_rest final_y] eqn:E.
    simpl.
    specialize (IH (S idx) (y0 + ul_height l)).
    rewrite E in IH. simpl in IH.
    lia.
Qed.

Corollary total_height_is_sum_line_heights : forall lines y0,
  final_offset lines y0 - y0 = sum_line_heights lines.
Proof.
  intros lines y0.
  unfold final_offset, stack_lines.
  rewrite blink_cursor_accumulation_correct.
  lia.
Qed.

(** ** 6. Proof of Requirement 2: Line Box Offset Progression (y_{k+1} = y_k + h_k) *)

(** Characterizes the exact attributes of the k-th placed line box. *)
Lemma nth_placed_line_characterization : forall lines idx y0 k d_pl d_ul,
  (k < length lines)%nat ->
  nth k (fst (stack_lines_aux lines idx y0)) d_pl =
    mkPlacedLine (idx + k)%nat
                 (y0 + sum_line_heights (firstn k lines))
                 (ul_height (nth k lines d_ul)).
Proof.
  induction lines as [| l rest IH]; intros idx y0 k d_pl d_ul Hk; simpl in *.
  - lia.
  - destruct (stack_lines_aux rest (S idx) (y0 + ul_height l)) as [placed_rest final_y] eqn:E.
    simpl. destruct k as [| k'].
    + simpl. f_equal; lia.
    + simpl.
      assert (Hk' : (k' < length rest)%nat) by lia.
      specialize (IH (S idx) (y0 + ul_height l) k' d_pl d_ul Hk').
      rewrite E in IH. simpl in IH.
      rewrite IH.
      f_equal; lia.
Qed.

(** Theorem: For any adjacent line boxes k and k+1, y_{k+1} = y_k + h_k. *)
Theorem offset_progression_recurrence : forall lines y0 k d,
  (S k < length lines)%nat ->
  let boxes := placed_boxes lines y0 in
  let box_k := nth k boxes d in
  let box_next := nth (S k) boxes d in
  pl_offset box_next = pl_offset box_k + pl_height box_k.
Proof.
  intros lines y0 k d Hk boxes box_k box_next.
  unfold box_k, box_next, boxes, placed_boxes, stack_lines.
  pose proof (nth_placed_line_characterization lines 0%nat y0 k d (mkUnplacedLine 0)) as H1.
  pose proof (nth_placed_line_characterization lines 0%nat y0 (S k) d (mkUnplacedLine 0)) as H2.
  assert (Hk1 : (k < length lines)%nat) by lia.
  rewrite H1 by exact Hk1.
  rewrite H2 by exact Hk.
  simpl.
  clear H1 H2 box_k box_next boxes.
  revert k Hk Hk1.
  induction lines as [| l rest IH]; intros k Hk Hk1; simpl in *.
  - lia.
  - destruct k as [| k']; simpl.
    + lia.
    + assert (IH_step : y0 + (ul_height l + sum_line_heights (firstn (S k') rest)) =
                        y0 + (ul_height l + sum_line_heights (firstn k' rest)) +
                        ul_height (nth k' rest (mkUnplacedLine 0))).
      { specialize (IH k' ltac:(lia) ltac:(lia)). lia. }
      lia.
Qed.

(** ** 7. Proofs of Requirement 3: Core Invariants *)

(** Invariant 3a: Total height non-negativity. *)
Theorem total_height_non_negative : forall lines,
  valid_line_list lines ->
  0 <= sum_line_heights lines.
Proof.
  intros lines Hvalid.
  induction Hvalid as [| l rest Hl Hrest IH]; simpl.
  - lia.
  - unfold valid_line_height in Hl. lia.
Qed.

Lemma firstn_valid_line_list : forall k lines,
  valid_line_list lines ->
  valid_line_list (firstn k lines).
Proof.
  induction k as [| k' IH]; intros lines Hvalid; simpl.
  - constructor.
  - destruct lines as [| l rest].
    + constructor.
    + inversion Hvalid; subst.
      constructor; auto.
Qed.

Lemma sum_line_heights_firstn_mono : forall lines i j,
  valid_line_list lines ->
  (i <= j)%nat ->
  sum_line_heights (firstn i lines) <= sum_line_heights (firstn j lines).
Proof.
  induction lines as [| l rest IH]; intros i j Hvalid Hij; simpl.
  - destruct i, j; simpl;