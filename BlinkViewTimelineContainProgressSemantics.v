Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink View Timeline Contain Range Semantics *)
(** Scroll-driven Animations 1 §3.2: contain range progress *)

Definition view_timeline_contain_progress (offset start_pos end_pos : Z) : Z :=
  let range := end_pos - start_pos in
  if range <=? 0 then 0
  else Z.max 0 (Z.min 1000 ((offset - start_pos) * 1000 / range)).

Theorem contain_progress_bounded : forall offset start_pos end_pos,
  0 <= view_timeline_contain_progress offset start_pos end_pos <= 1000.
Proof.
  intros offset start_pos end_pos.
  unfold view_timeline_contain_progress.
  destruct (end_pos - start_pos <=? 0); lia.
Qed.
