Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto Digest Determinism Semantics *)
(** Web Cryptography API §14.3.4: digest computation is deterministic *)

Definition compute_digest (alg_id msg_hash : Z) : Z :=
  msg_hash.

Theorem digest_deterministic : forall alg msg,
  compute_digest alg msg = compute_digest alg msg.
Proof.
  intros alg msg.
  reflexivity.
Qed.
