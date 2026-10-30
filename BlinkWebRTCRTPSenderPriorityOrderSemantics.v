Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC RTCRtpSender Priority Order Semantics *)
(** WebRTC 1.0 §5.2.2: very-low < low < medium < high *)

Definition PRIORITY_VERY_LOW : Z := 0.
Definition PRIORITY_LOW      : Z := 1.
Definition PRIORITY_MEDIUM   : Z := 2.
Definition PRIORITY_HIGH     : Z := 3.

Theorem rtp_sender_priority_strictly_monotonic :
  PRIORITY_VERY_LOW < PRIORITY_LOW /\
  PRIORITY_LOW < PRIORITY_MEDIUM /\
  PRIORITY_MEDIUM < PRIORITY_HIGH.
Proof.
  unfold PRIORITY_VERY_LOW, PRIORITY_LOW, PRIORITY_MEDIUM, PRIORITY_HIGH.
  lia.
Qed.
