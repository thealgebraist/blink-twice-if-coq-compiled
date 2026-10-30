From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* Blink LayoutNG Simplified Layout Fast Path *)
Fixpoint compute_block_offsets (start_y : Z) (child_heights : list Z) : list Z :=
  match child_heights with
  | nil => nil
  | h :: rest => start_y :: compute_block_offsets (start_y + h) rest
  end.

Theorem simplified_offsets_monotonic : forall hs start_y,
  (forall h, In h hs -> h >= 0) ->
  forall y1 y2 rest,
  compute_block_offsets start_y hs = y1 :: y2 :: rest ->
  y1 <= y2.
Proof.
  intros hs start_y Hpos y1 y2 rest Hcomp.
  destruct hs as [| h1 hs1]; [discriminate |].
  destruct hs1 as [| h2 hs2]; [discriminate |].
  cbn in Hcomp.
  injection Hcomp as E1 E2 Erest.
  subst y1 y2.
  assert (h1 >= 0) by (apply Hpos; left; reflexivity).
  lia.
Qed.
