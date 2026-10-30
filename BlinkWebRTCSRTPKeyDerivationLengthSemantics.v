Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC SRTP Key Derivation Length Semantics *)
(** RFC 5764 §4.2: key length preserved according to cipher suite *)

Definition CIPHER_AES_128_GCM : Z := 1.
Definition CIPHER_AES_256_GCM : Z := 2.

Definition srtp_key_length (cipher_suite : Z) : Z :=
  if cipher_suite =? CIPHER_AES_128_GCM then 16
  else if cipher_suite =? CIPHER_AES_256_GCM then 32
  else 0.

Theorem srtp_aes128_key_length_exact :
  srtp_key_length CIPHER_AES_128_GCM = 16.
Proof.
  reflexivity.
Qed.

Theorem srtp_aes256_key_length_exact :
  srtp_key_length CIPHER_AES_256_GCM = 32.
Proof.
  reflexivity.
Qed.
