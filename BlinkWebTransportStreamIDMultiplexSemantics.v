Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebTransport Stream ID Multiplexing Semantics *)
(** RFC 9000 §2.1: stream_id mod 4 specifies initiator and directionality *)

Definition is_client_initiated_stream (id : Z) : bool :=
  (id mod 4 =? 0) || (id mod 4 =? 2).

Definition is_bidirectional_stream (id : Z) : bool :=
  (id mod 4 =? 0) || (id mod 4 =? 1).

Theorem stream_0_is_client_bidirectional :
  is_client_initiated_stream 0 = true /\ is_bidirectional_stream 0 = true.
Proof.
  split; reflexivity.
Qed.

Theorem stream_3_is_server_unidirectional :
  is_client_initiated_stream 3 = false /\ is_bidirectional_stream 3 = false.
Proof.
  split; reflexivity.
Qed.
