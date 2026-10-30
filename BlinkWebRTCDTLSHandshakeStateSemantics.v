Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebRTC DTLS Handshake State Semantics *)
(** WebRTC 1.0 §5.5: DTLS transport connection state *)

Definition DTLS_STATE_NEW        : Z := 0.
Definition DTLS_STATE_CONNECTING : Z := 1.
Definition DTLS_STATE_CONNECTED  : Z := 2.
Definition DTLS_STATE_CLOSED     : Z := 3.
Definition DTLS_STATE_FAILED     : Z := 4.

Definition is_dtls_connected (st : Z) : bool :=
  st =? DTLS_STATE_CONNECTED.

Theorem dtls_connected_sound :
  is_dtls_connected DTLS_STATE_CONNECTED = true.
Proof.
  reflexivity.
Qed.

Theorem dtls_failed_not_connected :
  is_dtls_connected DTLS_STATE_FAILED = false.
Proof.
  reflexivity.
Qed.
