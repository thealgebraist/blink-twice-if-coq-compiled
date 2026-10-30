Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink RuleSet Bucket Hash Selection Semantics *)
(** Blink CSS Engine §3: rule bucket index within [0, num_buckets) *)

Definition compute_bucket_index (hash num_buckets : Z) : Z :=
  if num_buckets <=? 0 then 0
  else hash mod num_buckets.

Theorem bucket_index_bounded : forall h nb,
  0 < nb ->
  0 <= compute_bucket_index h nb < nb.
Proof.
  intros h nb Hnb.
  unfold compute_bucket_index.
  destruct (nb <=? 0) eqn:Heq.
  - apply Z.leb_le in Heq; lia.
  - apply Z.mod_pos_bound; exact Hnb.
Qed.
