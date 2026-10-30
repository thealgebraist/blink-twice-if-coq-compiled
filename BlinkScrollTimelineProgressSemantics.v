Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Timeline Progress Semantics *)
(** Scroll-driven Animations 1 §2: normalized progress calculation *)

Definition compute_scroll_progress (scroll start end_pos : Z) : Z :=
  let range := end_pos - start in
  if range <=? 0 then 0
  else Z.max 0 (Z.min 1000 ((scroll - start) * 1000 / range)).

Theorem scroll_progress_bounded : forall s start end_pos,
  0 <= compute_scroll_progress s start end_pos <= 1000.
Proof.
  intros s start end_pos.
  unfold compute_scroll_progress.
  destruct (end_pos - start <=? 0) eqn:Hr; lia.
Qed.
