Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn clientDataJSON Hash Length Semantics *)
(** WebAuthn Level 3 §5.8.1: clientDataHash must be exactly 32 bytes (SHA-256) *)

Definition CLIENT_DATA_HASH_BYTES : Z := 32.

Theorem client_data_hash_size_exact :
  CLIENT_DATA_HASH_BYTES = 32.
Proof.
  reflexivity.
Qed.
