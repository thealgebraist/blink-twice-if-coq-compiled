Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC RTP Sequence Number Wrap-Around Semantics *)
(** RFC 3550 §5.1: 16-bit sequence number wrap-around modulo 65536 *)

Definition next_rtp_sequence (seq : Z) : Z :=
  (seq + 1) mod 65536.

Theorem rtp_sequence_bounded : forall s,
  0 <= next_rtp_sequence s < 65536.
Proof.
  intros s.
  unfold next_rtp_sequence.
  apply Z.mod_pos_bound.
  lia.
Qed.

Theorem rtp_sequence_wraps_at_max :
  next_rtp_sequence 65535 = 0.
Proof.
  reflexivity.
Qed.
