Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Motion Path Offset Progress Semantics *)
(** Motion Path 1 §3: path progress calculation *)

Definition compute_path_progress (distance total_length : Z) : Z :=
  if total_length <=? 0 then 0
  else Z.max 0 (Z.min 1000 ((distance * 1000) / total_length)).

Theorem path_progress_bounded : forall d len,
  0 <= compute_path_progress d len <= 1000.
Proof.
  intros d len.
  unfold compute_path_progress.
  destruct (len <=? 0) eqn:Hlen; lia.
Qed.
