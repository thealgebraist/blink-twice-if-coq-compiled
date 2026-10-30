Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebCrypto AES-GCM Tag Length Verification Semantics *)
(** Web Cryptography API §21.2: tag length in {96, 104, 112, 120, 128} *)

Definition is_valid_tag_length (l : Z) : bool :=
  (l =? 96) || (l =? 104) || (l =? 112) || (l =? 120) || (l =? 128).

Theorem tag_length_128_valid :
  is_valid_tag_length 128 = true.
Proof.
  reflexivity.
Qed.

Theorem tag_length_64_invalid :
  is_valid_tag_length 64 = false.
Proof.
  reflexivity.
Qed.
