### Audit Report: Chromium Blink Table Column Location vs. CSS Table Module Level 3 (§3)

**Agent:** 210  
**Target:** Chromium Blink LayoutNG Table Column Location (`NGTableLayoutAlgorithm`) vs. W3C CSS Table Module Level 3, Section 3 (Table Layout / Grid Geometry)  
**Artifact:** `BlinkTableColumnLocationSemantics.v`

---

### 1. Offset Accumulation Semantics

In Chromium Blink's LayoutNG table engine (`ng_table_layout_algorithm.cc` and `ng_table_layout_algorithm_utils.cc`), physical/logical inline offsets for table columns are computed sequentially after distributing inline widths over the unified column grid (`NGTableColumnLocation`).

Given:
* $\text{border\_spacing}$: The inline horizontal border spacing (plus initial table inline border/padding offset $x_0$).
* $\text{col\_width}(i)$: The computed inline size of column $i$.

The inline starting offset $\text{col\_x}(i)$ of column $i$ is governed by the recurrence relation:
$$\text{col\_x}(0) = x_0$$
$$\text{col\_x}(i + 1) = \text{col\_x}(i) + \text{col\_width}(i) + \text{border\_spacing}$$

In CSS Table 3 §3, cells and columns occupy grid tracks separated by `border-spacing` (in the `separated` borders model; in the `collapsed` borders model, effective spacing between track origins reduces to $0$ while border widths are absorbed into track sizing/offsets). Blink represents each column via the struct:
```cpp
struct NGTableColumnLocation {
  LayoutUnit offset;
  LayoutUnit size;
  bool is_collapsed;
};
```
When iterating through the column sizes to populate `column_locations`, Blink maintains a running `column_offset` initialized to the inline start border/padding + `border_spacing.inline_size`, adding `column_size + border_spacing.inline_size` at each step.

---

### 2. Core Geometric Invariants

To guarantee absence of unintended cell overlap, deterministic hit-testing, and exact table inline intrinsic width attribution, Blink relies on two primary geometric invariants:

1. **Monotonicity / Strict Offset Advancement:**
   * **Non-Strict:** If $\forall k,\, \text{col\_width}(k) \ge 0$ and $\text{border\_spacing} \ge 0$, then for all $i < j$, $\text{col\_x}(i) \le \text{col\_x}(j)$.
   * **Strict:** If $\text{border\_spacing} > 0$ (or if $\text{col\_width}(k) > 0$ for all $k$), column offsets strictly advance:
     $$i < j \implies \text{col\_x}(i) < \text{col\_x}(j)$$

2. **Mutual Disjointness of Column Intervals:**
   Each column $i$ spans the half-open inline interval $I_i = [\text{col\_x}(i),\, \text{col\_x}(i) + \text{col\_width}(i))$.
   Under standard non-negativity constraints ($\text{col\_width}(k) \ge 0$ and $\text{border\_spacing} \ge 0$), for any two distinct columns $i \neq j$:
   $$I_i \cap I_j = \emptyset$$
   That is, no point $p$ can simultaneously satisfy $\text{col\_x}(i) \le p < \text{col\_x}(i) + \text{col\_width}(i)$ and $\text{col\_x}(j) \le p < \text{col\_x}(j) + \text{col\_width}(j)$. (Note: Even if a column has zero width, $I_i = [x, x) = \emptyset$, preserving disjointness trivially).

---

### 3. Formal Verification in Rocq / Coq (`BlinkTableColumnLocationSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization of Blink's table column location accumulation and its invariants, verified with **0 admits**.

```coq
(** * BlinkTableColumnLocationSemantics.v
    Formal Audit of Chromium Blink Table Column Location vs CSS Table 3 §3
    Agent 210 *)

From Coq Require Import Arith PeanoNat Lia List.
Import ListNotations.

Section TableColumnLocation.

  (** ** 1. Model Parameters and Offset Accumulation *)

  (** Initial offset (e.g., table inline-start border + padding + initial border-spacing) *)
  Variable x0 : nat.

  (** Inline border-spacing between adjacent columns *)
  Variable border_spacing : nat.

  (** Width of column [i] *)
  Variable col_width : nat -> nat.

  (** Recursive definition of column inline offset [col_x] *)
  Fixpoint col_x (i : nat) : nat :=
    match i with
    | 0 => x0
    | S i' => col_x i' + col_width i' + border_spacing
    end.

  (** Explicit recurrence equation matching specification:
      col_x(i+1) = col_x(i) + col_width(i) + border_spacing *)
  Theorem col_x_step : forall i : nat,
    col_x (i + 1) = col_x i + col_width i + border_spacing.
  Proof.
    intro i.
    replace (i + 1) with (S i) by lia.
    simpl. reflexivity.
  Qed.

  (** End offset of column [i]'s content box *)
  Definition col_end (i : nat) : nat :=
    col_x i + col_width i.

  (** Membership in the half-open interval [col_x(i), col_x(i) + col_width(i)) *)
  Definition in_col_interval (i : nat) (p : nat) : Prop :=
    col_x i <= p /\ p < col_end i.

  (** Mutual disjointness of two column intervals *)
  Definition intervals_disjoint (i j : nat) : Prop :=
    forall p : nat, ~ (in_col_interval i p /\ in_col_interval j p).


  (** ** 2. Offset Monotonicity and Advancement Invariants *)

  (** Non-strict bounding lemma: the end of column [i] does not exceed the start of [i+1] *)
  Lemma col_end_le_next_col_x : forall i : nat,
    col_end i <= col_x (S i).
  Proof.
    intro i.
    unfold col_end. simpl. lia.
  Qed.

  (** Weak monotonicity: column offsets never decrease as index increases *)
  Lemma col_x_monotonic_le : forall i d : nat,
    col_x i <= col_x (i + d).
  Proof.
    intros i d.
    induction d as [| d' IH].
    - replace (i + 0) with i by lia. lia.
    - replace (i + S d') with (S (i + d')) by lia.
      simpl. lia.
  Qed.

  (** General weak monotonicity for [i <= j] *)
  Theorem col_x_le_of_le : forall i j : nat,
    i <= j -> col_x i <= col_x j.
  Proof.
    intros i j Hle.
    replace j with (i + (j - i)) by lia.
    apply col_x_monotonic_le.
  Qed.

  (** Strong separation between [col_end i] and any subsequent column [j > i] *)
  Theorem col_end_le_subsequent_col_x : forall i j : nat,
    i < j -> col_end i <= col_x j.
  Proof.
    intros i j Hlt.
    assert (Hle : S i <= j) by lia.
    apply col_x_le_of_le in Hle.
    pose proof (col_end_le_next_col_x i) as Hend.
    lia.
  Qed.

  (** Strict advancement under positive border_spacing *)
  Theorem col_x_strict_advance_spacing : forall i j : nat,
    0 < border_spacing ->
    i < j ->
    col_x i < col_x j.
  Proof.
    intros i j Hbs Hlt.
    assert (Hle : S i <= j) by lia.
    apply col_x_le_of_le in Hle.
    simpl in Hle.
    lia.
  Qed.

  (** Strict advancement under positive column widths *)
  Theorem col_x_strict_advance_widths : forall i j : nat,
    (forall k : nat, 0 < col_width k) ->
    i < j ->
    col_x i < col_x j.
  Proof.
    intros i j Hw Hlt.
    assert (Hle : S i <= j) by lia.
    apply col_x_le_of_le in Hle.
    simpl in Hle.
    pose proof (Hw i) as Hwi.
    lia.
  Qed.

  (** Strict separation of column end and subsequent column start under positive border_spacing *)
  Theorem col_end_lt_subsequent_col_x : forall i j : nat,
    0 < border_spacing ->
    i < j ->
    col_end i < col_x j.
  Proof.
    intros i j Hbs Hlt.
    assert (Hle : S i <= j) by lia.
    apply col_x_le_of_le in Hle.
    unfold col_end. simpl in Hle.
    lia.
  Qed.


  (** ** 3. Mutual Disjointness of Column Intervals *)

  (** Helper: if [i < j], intervals [i] and [j] are disjoint *)
  Lemma intervals_disjoint_lt : forall i j : nat,
    i < j -> intervals_disjoint i j.
  Proof.
    intros i j Hlt p [Hi Hj].
    unfold in_col_interval in Hi, Hj.
    destruct Hi as [Hxi Hendi].
    destruct Hj as [Hxj Hendj].
    pose proof (col_end_le_subsequent_col_x i j Hlt) as Hsep.
    lia.
  Qed.

  (** Main Disjointness Theorem:
      For any two distinct columns [i <> j], their intervals
      [col_x(i), col_x(i) + col_width(i)) and [col_x(j), col_x(j) + col_width(j))
      are mutually disjoint, even when border_spacing = 0 or col_width = 0. *)
  Theorem col_intervals_mutually_disjoint : forall i j : nat,
    i <> j -> intervals_disjoint i j.
  Proof.
    intros i j Hneq p [Hi Hj].
    destruct (Nat.lt_trichotomy i j) as [Hlt | [Heq | Hgt]].
    - eapply intervals_disjoint_lt; [exact Hlt | split; eassumption].
    - contradiction.
    - eapply intervals_disjoint_lt; [exact Hgt | split; [exact Hj | exact Hi]].
  Qed.

  (** Unique Column Hit-Testing Corollary:
      Any inline coordinate [p] belongs to at most one column interval. *)
  Corollary unique_column_hit_test : forall i j p : nat,
    in_col_interval i p ->
    in_col_interval j p ->
    i = j.
  Proof.
    intros i j p Hi Hj.
    destruct (Nat.eq_dec i j) as [Heq | Hneq].
    - exact Heq.
    - exfalso.
      eapply (col_intervals_mutually_disjoint i j Hneq p).
      split; assumption.
  Qed.

End TableColumnLocation.

(** ** 4. Concrete List-Based LayoutNG Table Algorithm Model *)

Section BlinkLayoutNGColumnVector.

  (** Record mirroring Blink's [NGTableColumnLocation] *)
  Record NGTableColumnLocation := mkColLoc {
    loc_offset : nat;
    loc_size   : nat
  }.

  (** Iterative accumulation over a list of column widths, mirroring the loop in
      [NGTableLayoutAlgorithm::ComputeTableInlineSize] / [ComputeColumnLocations] *)
  Fixpoint compute_column_locations
           (curr_offset : nat)
           (border_spacing : nat)
           (widths : list nat) : list NGTableColumnLocation :=
    match widths with
    | [] => []
    | w :: ws =>
        mkColLoc curr_offset w ::
        compute_column_locations (curr_offset + w + border_spacing) border_spacing ws
    end.

  (** Equivalence between the functional list builder and the indexed recurrence [col_x] *)
  Theorem compute_column_locations_correct :
    forall (widths : list nat) (x0 border_spacing i : nat) (d : NGTableColumnLocation),
      i < length widths ->
      nth i (compute_column_locations x0 border_spacing widths) d =
      mkColLoc (col_x x0 border_spacing (fun k => nth k widths 0) i) (nth i widths 0).
  Proof.
    induction widths as [| w ws IH]; intros x0 bs i d Hlt.
    - simpl in Hlt. lia.
    - destruct i as [| i'].
      + simpl. reflexivity.
      + simpl in Hlt.
        assert (Hlt' : i' < length ws) by lia.
        simpl.
        rewrite (IH (x0 + w + bs) bs i' d Hlt').
        f_equal.
        generalize dependent x0.
        induction i' as [| k IHk]; intro x0.
        * simpl. reflexivity.
        * simpl. rewrite <- IHk. reflexivity.
  Qed.

End BlinkLayoutNGColumnVector.
```