Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Background Fetch Download Quota Semantics *)
(** Background Fetch API §4.1: downloadTotal non-negative quota *)

Definition is_valid_download_quota (total : Z) : bool :=
  0 <=? total.

Theorem download_quota_non_negative : forall total,
  is_valid_download_quota total = true <-> total >= 0.
Proof.
  intros total.
  unfold is_valid_download_quota.
  split; intro H.
  - apply Z.leb_le in H. lia.
  - apply Z.leb_le. lia.
Qed.
