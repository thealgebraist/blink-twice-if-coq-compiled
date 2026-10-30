Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink View Timeline Exit Range Semantics *)
(** Scroll-driven Animations 1 §3.4: exit range progress *)

Definition view_timeline_exit_progress (offset exit_start exit_end : Z) : Z :=
  let range := exit_end - exit_start in
  if range <=? 0 then 0
  else Z.max 0 (Z.min 1000 ((offset - exit_start) * 1000 / range)).

Theorem exit_progress_bounded : forall offset exit_start exit_end,
  0 <= view_timeline_exit_progress offset exit_start exit_end <= 1000.
Proof.
  intros offset exit_start exit_end.
  unfold view_timeline_exit_progress.
  destruct (exit_end - exit_start <=? 0); lia.
Qed.
