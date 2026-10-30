From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §4.2 Table Cell Rowspan Height Distribution *)
Fixpoint sum_heights (hs : list Z) : Z :=
  match hs with
  | nil => 0
  | h :: rest => h + sum_heights rest
  end.

Definition distribute_rowspan_deficit (cell_min_h : Z) (current_heights : list Z) : list Z :=
  let cur_sum := sum_heights current_heights in
  if cell_min_h <=? cur_sum then current_heights
  else
    let deficit := cell_min_h - cur_sum in
    match current_heights with
    | nil => nil
    | h0 :: rest => (h0 + deficit) :: rest
    end.

Theorem rowspan_distribution_satisfies_min : forall cell_min_h hs,
  hs <> nil ->
  sum_heights (distribute_rowspan_deficit cell_min_h hs) >= cell_min_h \/
  sum_heights hs >= cell_min_h.
Proof.
  intros cell_min_h [| h hs] Hnil; [contradiction Hnil; reflexivity |].
  unfold distribute_rowspan_deficit.
  destruct (cell_min_h <=? sum_heights (h :: hs)) eqn:E.
  - apply Z.leb_le in E. right. lia.
  - apply Z.leb_gt in E. left.
    cbn. lia.
Qed.
