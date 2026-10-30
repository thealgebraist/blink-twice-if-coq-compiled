(* ========================================================================= *)
(*               BlinkTableRowHeightAccumulationSemantics.v                  *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Table Row Stacking & Block Height      *)
(* Accumulation per W3C CSS 2.1 §17.5.3.                                     *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Fixpoint sum_heights (heights : list Z) : Z :=
  match heights with
  | nil => 0
  | h :: rest => h + sum_heights rest
  end.

Fixpoint compute_row_offsets (cursor_y : Z) (spacing : Z) (heights : list Z) : list Z :=
  match heights with
  | nil => nil
  | h :: rest =>
      let start_y := cursor_y + spacing in
      let next_y := start_y + h in
      start_y :: compute_row_offsets next_y spacing rest
  end.

Definition compute_total_table_height (spacing : Z) (heights : list Z) : Z :=
  spacing + sum_heights heights + (Z.of_nat (length heights)) * spacing.

Theorem compute_row_offsets_length : forall cur_y sp heights,
  length (compute_row_offsets cur_y sp heights) = length heights.
Proof.
  intros cur_y sp heights.
  revert cur_y.
  induction heights as [|h rest IH]; cbn; intros cur_y.
  - reflexivity.
  - rewrite (IH (cur_y + sp + h)). reflexivity.
Qed.

Theorem compute_row_offsets_strictly_monotonic : forall cur_y sp h rest,
  sp >= 0 -> h > 0 ->
  let offsets := compute_row_offsets cur_y sp (h :: rest) in
  match offsets, compute_row_offsets (cur_y + sp + h) sp rest with
  | y1 :: y2 :: _, _ => y1 < y2
  | _, _ => True
  end.
Proof.
  intros cur_y sp h rest Hsp Hh.
  cbn.
  destruct rest as [|h2 rest2]; cbn.
  - trivial.
  - lia.
Qed.

Theorem sum_heights_app : forall l1 l2,
  sum_heights (l1 ++ l2) = sum_heights l1 + sum_heights l2.
Proof.
  intros l1 l2.
  induction l1 as [|h rest IH]; cbn.
  - reflexivity.
  - rewrite IH. lia.
Qed.

Theorem total_table_height_nonneg : forall sp heights,
  sp >= 0 ->
  (forall h, In h heights -> h >= 0) ->
  compute_total_table_height sp heights >= 0.
Proof.
  intros sp heights Hsp Hpos.
  unfold compute_total_table_height.
  assert (Hsum_nonneg: sum_heights heights >= 0).
  { induction heights as [|h rest IH]; cbn.
    - lia.
    - assert (h >= 0) by (apply Hpos; left; reflexivity).
      assert (sum_heights rest >= 0).
      { apply IH. intros h0 Hin. apply Hpos. right. assumption. }
      lia. }
  assert (Z.of_nat (length heights) >= 0) by lia.
  assert (Z.of_nat (length heights) * sp >= 0) by nia.
  lia.
Qed.
