Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto RSA Modulus Length Semantics *)
(** Web Cryptography API §23.2: minimum modulus length 2048 bits *)

Definition is_valid_rsa_modulus_length (bits : Z) : bool :=
  2048 <=? bits.

Theorem rsa_2048_valid :
  is_valid_rsa_modulus_length 2048 = true.
Proof.
  reflexivity.
Qed.

Theorem rsa_1024_invalid :
  is_valid_rsa_modulus_length 1024 = false.
Proof.
  reflexivity.
Qed.
