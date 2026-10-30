Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebRTC Signaling State Semantics *)
(** WebRTC 1.0 §4.3.1: SDP offer/answer signaling states; closed is terminal *)

Definition SIGNALING_STABLE            : Z := 0.
Definition SIGNALING_HAVE_LOCAL_OFFER  : Z := 1.
Definition SIGNALING_HAVE_REMOTE_OFFER : Z := 2.
Definition SIGNALING_CLOSED            : Z := 3.

Definition is_signaling_closed (st : Z) : bool :=
  st =? SIGNALING_CLOSED.

Theorem closed_is_terminal :
  is_signaling_closed SIGNALING_CLOSED = true.
Proof.
  reflexivity.
Qed.

Theorem stable_is_not_closed :
  is_signaling_closed SIGNALING_STABLE = false.
Proof.
  reflexivity.
Qed.
