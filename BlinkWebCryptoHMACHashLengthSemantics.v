Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto HMAC Digest Length Semantics *)
(** Web Cryptography API §28.2: HMAC output length matches underlying hash *)

Definition hmac_output_bytes (hash_alg : Z) : Z :=
  if hash_alg =? 256 then 32
  else if hash_alg =? 512 then 64
  else 0.

Theorem hmac_sha256_output_32 :
  hmac_output_bytes 256 = 32.
Proof.
  reflexivity.
Qed.

Theorem hmac_sha512_output_64 :
  hmac_output_bytes 512 = 64.
Proof.
  reflexivity.
Qed.
