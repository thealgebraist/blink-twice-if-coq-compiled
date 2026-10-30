(* ========================================================================= *)
(*               BlinkTableAutoColumnSizingSemantics.v                       *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Automatic Table Column Width           *)
(* Distribution per W3C CSS 2.1 §17.5.2.2.                                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition distribute_2cols
  (min1 max1 min2 max2 avail_w : Z) : Z * Z :=
  let s_min := min1 + min2 in
  let s_max := max1 + max2 in
  if avail_w <=? s_min then
    (min1, min2)
  else if avail_w <=? s_max then
    let excess := avail_w - s_min in
    let span_diff := s_max - s_min in
    if span_diff <=? 0 then (min1, min2)
    else
      let d1 := (excess * (max1 - min1)) / span_diff in
      (min1 + d1, avail_w - (min1 + d1))
  else
    let excess := avail_w - s_max in
    let extra1 := excess / 2 in
    (max1 + extra1, avail_w - (max1 + extra1)).

Theorem distribute_2cols_width_conservation : forall min1 max1 min2 max2 avail_w,
  avail_w >= min1 + min2 ->
  fst (distribute_2cols min1 max1 min2 max2 avail_w) +
  snd (distribute_2cols min1 max1 min2 max2 avail_w) = avail_w.
Proof.
  intros min1 max1 min2 max2 avail_w Hge.
  unfold distribute_2cols.
  destruct (avail_w <=? min1 + min2) eqn:Hle_min.
  - apply Z.leb_le in Hle_min.
    assert (avail_w = min1 + min2) by lia.
    subst. cbn. lia.
  - destruct (avail_w <=? max1 + max2) eqn:Hle_max.
    + destruct (max1 + max2 - (min1 + min2) <=? 0) eqn:Hdiff.
      * apply Z.leb_gt in Hle_min.
        apply Z.leb_le in Hdiff.
        apply Z.leb_le in Hle_max.
        lia.
      * cbn. lia.
    + cbn. lia.
Qed.

Theorem distribute_2cols_satisfies_min : forall min1 max1 min2 max2 avail_w,
  min1 <= max1 ->
  min2 <= max2 ->
  avail_w >= min1 + min2 ->
  fst (distribute_2cols min1 max1 min2 max2 avail_w) >= min1 /\
  snd (distribute_2cols min1 max1 min2 max2 avail_w) >= min2.
Proof.
  intros min1 max1 min2 max2 avail_w Hmin1 Hmin2 Hw.
  unfold distribute_2cols.
  destruct (avail_w <=? min1 + min2) eqn:Hle_min; cbn.
  - lia.
  - apply Z.leb_gt in Hle_min.
    destruct (avail_w <=? max1 + max2) eqn:Hle_max; cbn.
    + destruct (max1 + max2 - (min1 + min2) <=? 0) eqn:Hdiff; cbn.
      * apply Z.leb_le in Hdiff. lia.
      * apply Z.leb_gt in Hdiff.
        apply Z.leb_le in Hle_max.
        assert (Hexc_pos: avail_w - (min1 + min2) >= 0) by lia.
        assert (Hmax_sub1: max1 - min1 >= 0) by lia.
        assert (Hmax_sub2: max2 - min2 >= 0) by lia.
        assert (Hd1_pos: (avail_w - (min1 + min2)) * (max1 - min1) >= 0) by nia.
        assert (0 <= ((avail_w - (min1 + min2)) * (max1 - min1)) / (max1 + max2 - (min1 + min2))).
        { apply Z.div_pos; lia. }
        assert (((avail_w - (min1 + min2)) * (max1 - min1)) / (max1 + max2 - (min1 + min2)) <= avail_w - (min1 + min2)).
        { apply Z.div_le_upper_bound; [lia |].
          assert (max1 - min1 <= max1 + max2 - (min1 + min2)) by lia.
          nia. }
        lia.
    + apply Z.leb_gt in Hle_max.
      assert (avail_w - (max1 + max2) >= 0) by lia.
      assert (0 <= (avail_w - (max1 + max2)) / 2).
      { apply Z.div_pos; lia. }
      assert ((avail_w - (max1 + max2)) / 2 <= avail_w - (max1 + max2)).
      { apply Z.div_le_upper_bound; lia. }
      lia.
Qed.

Theorem distribute_2cols_nonneg : forall min1 max1 min2 max2 avail_w,
  min1 >= 0 -> min2 >= 0 ->
  min1 <= max1 -> min2 <= max2 ->
  avail_w >= min1 + min2 ->
  fst (distribute_2cols min1 max1 min2 max2 avail_w) >= 0 /\
  snd (distribute_2cols min1 max1 min2 max2 avail_w) >= 0.
Proof.
  intros min1 max1 min2 max2 avail_w H0_1 H0_2 Hmin1 Hmin2 Hw.
  pose proof (distribute_2cols_satisfies_min min1 max1 min2 max2 avail_w Hmin1 Hmin2 Hw) as [H1 H2].
  lia.
Qed.

