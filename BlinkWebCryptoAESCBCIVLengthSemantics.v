Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto AES-CBC IV Length Semantics *)
(** Web Cryptography API §20.2: IV length must be exactly 16 bytes *)

Definition is_valid_cbc_iv_length (l : Z) : bool :=
  l =? 16.

Theorem cbc_iv_16_valid :
  is_valid_cbc_iv_length 16 = true.
Proof.
  reflexivity.
Qed.

Theorem cbc_iv_12_invalid :
  is_valid_cbc_iv_length 12 = false.
Proof.
  reflexivity.
Qed.
