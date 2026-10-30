Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebCrypto getRandomValues Quota Bounding Semantics *)
(** Web Cryptography API §10.1: requested byte length <= 65536 *)

Definition MAX_RANDOM_BYTES : Z := 65536.

Definition is_valid_random_quota (sz : Z) : bool :=
  (0 <=? sz) && (sz <=? MAX_RANDOM_BYTES).

Theorem random_quota_bounded : forall sz,
  is_valid_random_quota sz = true <-> (0 <= sz /\ sz <= MAX_RANDOM_BYTES).
Proof.
  intros sz.
  unfold is_valid_random_quota, MAX_RANDOM_BYTES.
  rewrite andb_true_iff, Z.leb_le, Z.leb_le.
  tauto.
Qed.
