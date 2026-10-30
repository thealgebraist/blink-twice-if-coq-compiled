Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Storage Quota Bounding Semantics *)
(** Storage Standard §3: writes cannot exceed allocated storage quota *)

Definition safe_storage_write (current_usage delta quota : Z) : Z :=
  if current_usage + delta <=? quota then current_usage + delta
  else current_usage.

Theorem safe_storage_write_bounded : forall u d q,
  0 <= u <= q ->
  0 <= d ->
  safe_storage_write u d q <= q.
Proof.
  intros u d q Hu Hd.
  unfold safe_storage_write.
  destruct (u + d <=? q) eqn:Heq.
  - apply Z.leb_le in Heq. lia.
  - lia.
Qed.

Theorem safe_storage_write_monotonic : forall u d q,
  0 <= u ->
  0 <= d ->
  u <= safe_storage_write u d q.
Proof.
  intros u d q Hu Hd.
  unfold safe_storage_write.
  destruct (u + d <=? q) eqn:Heq; lia.
Qed.
