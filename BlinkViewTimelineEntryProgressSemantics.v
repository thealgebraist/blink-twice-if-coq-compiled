Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink View Timeline Entry Range Semantics *)
(** Scroll-driven Animations 1 §3.3: entry range progress *)

Definition view_timeline_entry_progress (offset entry_start entry_end : Z) : Z :=
  let range := entry_end - entry_start in
  if range <=? 0 then 0
  else Z.max 0 (Z.min 1000 ((offset - entry_start) * 1000 / range)).

Theorem entry_progress_bounded : forall offset entry_start entry_end,
  0 <= view_timeline_entry_progress offset entry_start entry_end <= 1000.
Proof.
  intros offset entry_start entry_end.
  unfold view_timeline_entry_progress.
  destruct (entry_end - entry_start <=? 0); lia.
Qed.
