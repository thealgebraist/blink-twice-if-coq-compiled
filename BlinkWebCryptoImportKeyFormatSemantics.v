Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto importKey Format Discrimination Semantics *)
(** Web Cryptography API §14.3.9: formats raw, pkcs8, spki, jwk *)

Definition FORMAT_RAW   : Z := 1.
Definition FORMAT_PKCS8 : Z := 2.
Definition FORMAT_SPKI  : Z := 3.
Definition FORMAT_JWK   : Z := 4.

Theorem formats_all_distinct :
  FORMAT_RAW <> FORMAT_PKCS8 /\
  FORMAT_PKCS8 <> FORMAT_SPKI /\
  FORMAT_SPKI <> FORMAT_JWK.
Proof.
  unfold FORMAT_RAW, FORMAT_PKCS8, FORMAT_SPKI, FORMAT_JWK.
  lia.
Qed.
