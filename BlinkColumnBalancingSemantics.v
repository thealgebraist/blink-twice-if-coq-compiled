(**
  BlinkColumnBalancingSemantics.v
  Formal specification of Chromium Blink multi-column column balancing and bisection
  derived from third_party/blink/renderer/core/layout/fragmentation/column_layout_algorithm.cc
  according to W3C CSS Multi-column Layout Module Level 1 (§4 Column Balancing Iterative Solver).
*)

From Stdlib Require Import ZArith.BinInt.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Initial Column Balancing Search Bracket *)

Definition compute_initial_min (total_height monolithic_height column_count : Z) : Z :=
  if column_count <=? 0 then total_height
  else
    let avg := (total_height + column_count - 1) / column_count in
    Z.max monolithic_height avg.

Definition compute_initial_max (total_height : Z) : Z :=
  total_height.

Theorem initial_min_bounds_monolithic :
  forall total_h mono_h n : Z,
    0 < n ->
    mono_h <= compute_initial_min total_h mono_h n.
Proof.
  intros total_h mono_h n Hn.
  unfold compute_initial_min.
  destruct (n <=? 0) eqn:En; [lia|].
  apply Z.le_max_l.
Qed.

Theorem initial_min_bounds_average :
  forall total_h mono_h n : Z,
    0 < n ->
    (total_h + n - 1) / n <= compute_initial_min total_h mono_h n.
Proof.
  intros total_h mono_h n Hn.
  unfold compute_initial_min.
  destruct (n <=? 0) eqn:En; [lia|].
  apply Z.le_max_r.
Qed.

Theorem initial_bracket_valid :
  forall total_h mono_h n : Z,
    0 < n ->
    0 <= total_h ->
    mono_h <= total_h ->
    compute_initial_min total_h mono_h n <= compute_initial_max total_h.
Proof.
  intros total_h mono_h n Hn Hpos Hmono.
  unfold compute_initial_min, compute_initial_max.
  destruct (n <=? 0) eqn:En; [lia|].
  apply Z.max_lub.
  - exact Hmono.
  - destruct (Z.eq_dec total_h 0).
    + subst.
      assert (0 <= n - 1 < n) by lia.
      rewrite Z.div_small by lia.
      lia.
    + assert (total_h + n - 1 <= total_h * n).
      {
        destruct (Z.eq_dec n 1).
        - subst. lia.
        - assert (n >= 2) by lia. nia.
      }
      assert (Hdiv : (total_h + n - 1) / n <= (total_h * n) / n).
      { apply Z.div_le_mono; lia. }
      rewrite Z.div_mul in Hdiv by lia.
      exact Hdiv.
Qed.

(** 2. Bisection Midpoint and Contraction *)

Definition bisection_midpoint (h_min h_max : Z) : Z :=
  (h_min + h_max) / 2.

Theorem bisection_midpoint_bounds :
  forall h_min h_max : Z,
    h_min <= h_max ->
    h_min <= bisection_midpoint h_min h_max <= h_max.
Proof.
  intros h_min h_max Hle.
  unfold bisection_midpoint.
  split.
  - assert (H2 : h_min * 2 <= h_min + h_max) by lia.
    assert (Hdiv : (h_min * 2) / 2 <= (h_min + h_max) / 2) by (apply Z.div_le_mono; lia).
    rewrite Z.div_mul in Hdiv by lia.
    exact Hdiv.
  - assert (H2 : h_min + h_max <= h_max * 2) by lia.
    assert (Hdiv : (h_min + h_max) / 2 <= (h_max * 2) / 2) by (apply Z.div_le_mono; lia).
    rewrite Z.div_mul in Hdiv by lia.
    exact Hdiv.
Qed.

Theorem bisection_interval_strictly_contracts :
  forall h_min h_max : Z,
    h_min < h_max ->
    let mid := bisection_midpoint h_min h_max in
    (mid - h_min < h_max - h_min) /\ (h_max - (mid + 1) < h_max - h_min).
Proof.
  intros h_min h_max Hlt mid.
  unfold mid, bisection_midpoint.
  assert (Hmid_le : (h_min + h_max) / 2 <= h_max).
  {
    assert (H2 : h_min + h_max <= h_max * 2) by lia.
    assert (Hdiv : (h_min + h_max) / 2 <= (h_max * 2) / 2) by (apply Z.div_le_mono; lia).
    rewrite Z.div_mul in Hdiv by lia.
    exact Hdiv.
  }
  assert (Hmid_ge : h_min <= (h_min + h_max) / 2).
  {
    assert (H2 : h_min * 2 <= h_min + h_max) by lia.
    assert (Hdiv : (h_min * 2) / 2 <= (h_min + h_max) / 2) by (apply Z.div_le_mono; lia).
    rewrite Z.div_mul in Hdiv by lia.
    exact Hdiv.
  }
  assert (Hmid_strict : (h_min + h_max) / 2 < h_max).
  {
    assert (h_min + h_max < 2 * h_max) by lia.
    apply Z.div_lt_upper_bound; lia.
  }
  split; lia.
Qed.

(** 3. Column Capacity Simulation *)

Fixpoint pack_items_into_columns (items : list Z) (h_cand : Z) (current_col_rem : Z) : Z :=
  match items with
  | [] => 1
  | x :: xs =>
      if x <=? current_col_rem then
        pack_items_into_columns xs h_cand (current_col_rem - x)
      else
        1 + pack_items_into_columns xs h_cand (h_cand - x)
  end.

Theorem pack_empty_needs_one_column :
  forall h_cand rem,
    pack_items_into_columns [] h_cand rem = 1.
Proof.
  intros. reflexivity.
Qed.

Theorem pack_nonnegative :
  forall items h_cand rem,
    1 <= pack_items_into_columns items h_cand rem.
Proof.
  intros items.
  induction items as [|x xs IH].
  - intros h_cand rem. simpl. lia.
  - intros h_cand rem.
    cbn [pack_items_into_columns].
    destruct (x <=? rem).
    + apply IH.
    + specialize (IH h_cand (h_cand - x)).
      lia.
Qed.
