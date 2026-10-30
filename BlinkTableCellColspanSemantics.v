From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §3.2 Table Cell Colspan Width Distribution *)
Fixpoint sum_widths (ws : list Z) : Z :=
  match ws with
  | nil => 0
  | w :: rest => w + sum_widths rest
  end.

Definition distribute_colspan_deficit (cell_min_w : Z) (current_widths : list Z) : list Z :=
  let cur_sum := sum_widths current_widths in
  if cell_min_w <=? cur_sum then current_widths
  else
    let deficit := cell_min_w - cur_sum in
    match current_widths with
    | nil => nil
    | w0 :: rest => (w0 + deficit) :: rest
    end.

Theorem colspan_distribution_satisfies_min : forall cell_min_w ws,
  ws <> nil ->
  sum_widths (distribute_colspan_deficit cell_min_w ws) >= cell_min_w \/
  sum_widths ws >= cell_min_w.
Proof.
  intros cell_min_w [| w ws] Hnil; [contradiction Hnil; reflexivity |].
  unfold distribute_colspan_deficit.
  destruct (cell_min_w <=? sum_widths (w :: ws)) eqn:E.
  - apply Z.leb_le in E. right. lia.
  - apply Z.leb_gt in E. left.
    cbn. lia.
Qed.
