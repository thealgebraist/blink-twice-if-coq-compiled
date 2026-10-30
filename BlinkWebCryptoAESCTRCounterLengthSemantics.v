Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto AES-CTR Counter Length Semantics *)
(** Web Cryptography API §22.2: counter length must be exactly 16 bytes *)

Definition is_valid_ctr_counter_length (l : Z) : bool :=
  l =? 16.

Theorem ctr_counter_16_valid :
  is_valid_ctr_counter_length 16 = true.
Proof.
  reflexivity.
Qed.

Theorem ctr_counter_8_invalid :
  is_valid_ctr_counter_length 8 = false.
Proof.
  reflexivity.
Qed.
