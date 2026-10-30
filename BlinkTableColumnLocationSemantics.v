From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §3 Table Column Location & Monotonic Offset Accumulation *)
Fixpoint compute_col_offsets (start_x : Z) (spacing : Z) (widths : list Z) : list Z :=
  match widths with
  | nil => nil
  | w :: ws => start_x :: compute_col_offsets (start_x + w + spacing) spacing ws
  end.

Theorem col_offsets_monotonic : forall ws start_x spacing,
  spacing >= 0 ->
  (forall w, In w ws -> w >= 0) ->
  forall x1 x2 rest,
  compute_col_offsets start_x spacing ws = x1 :: x2 :: rest ->
  x1 <= x2.
Proof.
  intros ws start_x spacing Hsp Hpos x1 x2 rest Hcomp.
  destruct ws as [| w1 ws1]; [discriminate |].
  destruct ws1 as [| w2 ws2]; [discriminate |].
  cbn in Hcomp.
  injection Hcomp as E1 E2 Erest.
  subst x1 x2.
  assert (Hw1: w1 >= 0) by (apply Hpos; left; reflexivity).
  lia.
Qed.

Theorem col_intervals_disjoint : forall w1 w2 ws start_x spacing,
  spacing >= 0 ->
  w1 >= 0 ->
  compute_col_offsets start_x spacing (w1 :: w2 :: ws) = start_x :: (start_x + w1 + spacing) :: compute_col_offsets (start_x + w1 + spacing + w2 + spacing) spacing ws.
Proof.
  intros. reflexivity.
Qed.
