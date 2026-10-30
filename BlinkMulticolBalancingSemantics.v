(* ========================================================================= *)
(*               BlinkMulticolBalancingSemantics.v                          *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Multi-Column Column Count          *)
(* Calculation against CSS Multi-column 1 §3.4. Fully constructive.         *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition compute_multicol_column_count (w_avail col_w gap : Z) : Z :=
  Z.max 1 ((w_avail + gap) / (col_w + gap)).

Definition total_multicol_width (n col_w gap : Z) : Z :=
  if n <=? 0 then 0
  else n * col_w + (n - 1) * gap.

Theorem multicol_column_count_ge_1 : forall w_avail col_w gap,
  compute_multicol_column_count w_avail col_w gap >= 1.
Proof.
  intros. unfold compute_multicol_column_count. lia.
Qed.

Theorem multicol_used_width_bounded : forall w_avail col_w gap,
  col_w > 0 ->
  gap >= 0 ->
  w_avail >= col_w ->
  let n := compute_multicol_column_count w_avail col_w gap in
  total_multicol_width n col_w gap <= w_avail.
Proof.
  intros w_avail col_w gap Hcol Hgap Hw n.
  unfold n, compute_multicol_column_count, total_multicol_width.
  assert (Hdenom: 0 < col_w + gap) by lia.
  assert (Hnum: col_w + gap <= w_avail + gap) by lia.
  assert (Hdiv: (w_avail + gap) / (col_w + gap) >= 1).
  {
    apply Z.le_ge.
    apply Z.div_le_lower_bound; lia.
  }
  assert (Heq: Z.max 1 ((w_avail + gap) / (col_w + gap)) = (w_avail + gap) / (col_w + gap)) by lia.
  rewrite Heq.
  assert (Hcond: ((w_avail + gap) / (col_w + gap) <=? 0) = false).
  { apply Z.leb_gt. lia. }
  rewrite Hcond.
  pose proof (Z.mul_div_le (w_avail + gap) (col_w + gap) Hdenom) as Hle.
  assert (Halg: ((w_avail + gap) / (col_w + gap)) * col_w + (((w_avail + gap) / (col_w + gap)) - 1) * gap =
                ((w_avail + gap) / (col_w + gap)) * (col_w + gap) - gap) by ring.
  rewrite Halg.
  lia.
Qed.
