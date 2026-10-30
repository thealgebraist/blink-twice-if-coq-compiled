# Audit Report: Agent 185
**Target**: Chromium Blink Inline Text Ellipsis Truncation (`third_party/blink/renderer/core/layout/inline/inline_box_state.cc`, `line_truncator.cc`)  
**Specification**: W3C CSS Overflow Module Level 3 §4.2 (`text-overflow: ellipsis`)

---

## 1. Truncation Algorithm Analysis

Under CSS Overflow 3 §4.2, when inline content overflows its line box edge and `text-overflow: ellipsis` is active, the user agent must hide characters and atomic inline-level elements at the end edge of the line so that the ellipsis fits within the available line width.

In Chromium Blink's LayoutNG (`NGLineTruncator`), truncation operates over text fragments on the line:
1. Given an `available_width` $W_{\text{avail}}$, an `ellipsis_width` $W_{\text{ellipsis}}$, and a sequence of character (or grapheme cluster) widths $[w_0, w_1, \dots, w_{n-1}]$ of length $N = \text{total\_chars}$.
2. If the full text width $\sum_{k=0}^{N-1} w_k \le W_{\text{avail}}$, no truncation occurs.
3. When truncation is invoked (under the precondition that $W_{\text{ellipsis}} \le W_{\text{avail}}$), Blink searches for the **largest character index** $i \in [0, N]$ such that the cumulative prefix width plus the ellipsis width does not exceed the available width:
   $$\text{width}([0, i)) + W_{\text{ellipsis}} \le W_{\text{avail}}$$
   where $\text{width}([0, i)) = \sum_{k=0}^{i-1} w_k$.

---

## 2. Core Formal Invariants

Assuming $W_{\text{ellipsis}} \le W_{\text{avail}}$ and non-negative character advance widths ($w_k \ge 0$):

1. **Width Bound Invariant**: The rendered width of the truncated text prefix $[0, i)$ combined with the ellipsis width never overflows the available width:
   $$\text{prefix\_width}(i) + W_{\text{ellipsis}} \le W_{\text{avail}}$$
2. **Index Validity Invariant**: The computed truncation index $i$ is strictly bounded within the valid character cursor range of the text run:
   $$0 \le i \le \text{total\_chars}$$
3. **Maximality (Optimality) Invariant**: For any valid index $j \le \text{total\_chars}$, if $\text{prefix\_width}(j) + W_{\text{ellipsis}} \le W_{\text{avail}}$, then $j \le i$.

---

## 3. Formal Verification in Rocq / Coq

Below is the complete, self-contained formalization for `BlinkTextEllipsisTruncationSemantics.v`.

```coq
(** * BlinkTextEllipsisTruncationSemantics.v
    Formal verification of Chromium Blink Text Ellipsis Truncation
    against CSS Overflow Module Level 3 §4.2. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Section EllipsisTruncation.

  (** We represent layout units (e.g., Blink's LayoutUnit) as natural numbers
      representing non-negative subpixel quanta. *)
  Definition LayoutUnit := nat.

  (** [prefix_width widths i] computes the width of the slice [0, i). *)
  Fixpoint prefix_width (widths : list LayoutUnit) (i : nat) : LayoutUnit :=
    match i, widths with
    | 0, _ => 0
    | S _, [] => 0
    | S i', w :: ws => w + prefix_width ws i'
    end.

  (** Predicate stating that truncating at index [i] fits within [avail_w]
      when accounting for [ellipsis_w]. *)
  Definition fits_with_ellipsis (widths : list LayoutUnit) (ellipsis_w avail_w : LayoutUnit) (i : nat) : Prop :=
    prefix_width widths i + ellipsis_w <= avail_w.

  (** Boolean decision procedure for [fits_with_ellipsis]. *)
  Definition fits_with_ellipsis_b (widths : list LayoutUnit) (ellipsis_w avail_w : LayoutUnit) (i : nat) : bool :=
    (prefix_width widths i + ellipsis_w <=? avail_w).

  (** [find_max_truncation_aux widths ellipsis_w avail_w k] searches downward
      from [k] to 0 for the largest index that fits with the ellipsis. *)
  Fixpoint find_max_truncation_aux (widths : list LayoutUnit) (ellipsis_w avail_w : LayoutUnit) (k : nat) : nat :=
    if fits_with_ellipsis_b widths ellipsis_w avail_w k then
      k
    else
      match k with
      | 0 => 0
      | S k' => find_max_truncation_aux widths ellipsis_w avail_w k'
      end.

  (** Top-level Blink truncation index selector over a character width list. *)
  Definition truncate_index (widths : list LayoutUnit) (ellipsis_w avail_w : LayoutUnit) : nat :=
    find_max_truncation_aux widths ellipsis_w avail_w (length widths).

  (** ** Helper Lemmas *)

  Lemma prefix_width_zero : forall widths,
    prefix_width widths 0 = 0.
  Proof.
    intros widths. reflexivity.
  Qed.

  Lemma prefix_width_mono : forall widths i j,
    i <= j -> prefix_width widths i <= prefix_width widths j.
  Proof.
    induction widths as [|w ws IH]; intros i j Hle.
    - destruct i; destruct j; simpl; lia.
    - destruct i as [|i']; destruct j as [|j']; simpl; try lia.
      assert (Hi_le_j: i' <= j') by lia.
      specialize (IH i' j' Hi_le_j).
      lia.
  Qed.

  Lemma fits_with_ellipsis_b_spec : forall widths ellipsis_w avail_w i,
    fits_with_ellipsis_b widths ellipsis_w avail_w i = true <->
    fits_with_ellipsis widths ellipsis_w avail_w i.
  Proof.
    intros widths ellipsis_w avail_w i.
    unfold fits_with_ellipsis_b, fits_with_ellipsis.
    rewrite Nat.leb_le.
    tauto.
  Qed.

  (** ** Main Invariant Theorems *)

  (** Theorem 1 (Index Bound Invariant):
      The truncation index is always bounded in [0, total_chars]. *)
  Lemma find_max_truncation_aux_bound : forall widths ellipsis_w avail_w k,
    find_max_truncation_aux widths ellipsis_w avail_w k <= k.
  Proof.
    induction k as [|k' IH]; simpl.
    - destruct (fits_with_ellipsis_b widths ellipsis_w avail_w 0); lia.
    - destruct (fits_with_ellipsis_b widths ellipsis_w avail_w (S k')); lia.
  Qed.

  Theorem truncation_index_bounded : forall widths ellipsis_w avail_w,
    0 <= truncate_index widths ellipsis_w avail_w <= length widths.
  Proof.
    intros widths ellipsis_w avail_w.
    unfold truncate_index.
    split.
    - lia.
    - apply find_max_truncation_aux_bound.
  Qed.

  (** Theorem 2 (Width Bound Invariant):
      Assuming ellipsis_width <= available_width, the truncated text width
      plus ellipsis_width never exceeds available_width. *)
  Lemma find_max_truncation_aux_fits : forall widths ellipsis_w avail_w k,
    ellipsis_w <= avail_w ->
    fits_with_ellipsis widths ellipsis_w avail_w (find_max_truncation_aux widths ellipsis_w avail_w k).
  Proof.
    induction k as [|k' IH]; intros Hellipsis; simpl.
    - destruct (fits_with_ellipsis_b widths ellipsis_w avail_w 0) eqn:Hfit.
      + apply fits_with_ellipsis_b_spec; exact Hfit.
      + unfold fits_with_ellipsis. simpl. lia.
    - destruct (fits_with_ellipsis_b widths ellipsis_w avail_w (S k')) eqn:Hfit.
      + apply fits_with_ellipsis_b_spec; exact Hfit.
      + apply IH; exact Hellipsis.
  Qed.

  Theorem truncated_width_invariant : forall widths ellipsis_w avail_w,
    ellipsis_w <= avail_w ->
    prefix_width widths (truncate_index widths ellipsis_w avail_w) + ellipsis_w <= avail_w.
  Proof.
    intros widths ellipsis_w avail_w Hellipsis.
    unfold truncate_index.
    apply (find_max_truncation_aux_fits widths ellipsis_w avail_w (length widths) Hellipsis).
  Qed.

  (** Theorem 3 (Maximality Specification):
      The computed index is the LARGEST index in [0, total_chars] that satisfies
      the width constraint. *)
  Lemma find_max_truncation_aux_maximal : forall widths ellipsis_w avail_w k j,
    j <= k ->
    fits_with_ellipsis widths ellipsis_w avail_w j ->
    j <= find_max_truncation_aux widths ellipsis_w avail_w k.
  Proof.
    induction k as [|k' IH]; intros j Hj_le Hfit; simpl.
    - lia.
    - destruct (fits_with_ellipsis_b widths ellipsis_w avail_w (S k')) eqn:Hfit_Sk.
      + exact Hj_le.
      + assert (Hj_neq : j <> S k').
        { intro Heq. subst j.
          apply fits_with_ellipsis_b_spec in Hfit.
          congruence. }
        assert (Hj_le_k' : j <= k') by lia.
        apply IH; assumption.
  Qed.

  Theorem truncation_index_is_largest : forall widths ellipsis_w avail_w j,
    j <= length widths ->
    prefix_width widths j + ellipsis_w <= avail_w ->
    j <= truncate_index widths ellipsis_w avail_w.
  Proof.
    intros widths ellipsis_w avail_w j Hj_bound Hj_fits.
    unfold truncate_index.
    apply find_max_truncation_aux_maximal.
    - exact Hj_bound.
    - unfold fits_with_ellipsis. exact Hj_fits.
  Qed.

End EllipsisTruncation.
```