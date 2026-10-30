Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC ICE Candidate Gathering State Semantics *)
(** WebRTC 1.0 §4.3.2: monotonic progression new < gathering < complete *)

Definition ICE_GATHERING_NEW       : Z := 0.
Definition ICE_GATHERING_GATHERING : Z := 1.
Definition ICE_GATHERING_COMPLETE  : Z := 2.

Theorem gathering_state_strictly_increasing :
  ICE_GATHERING_NEW < ICE_GATHERING_GATHERING /\
  ICE_GATHERING_GATHERING < ICE_GATHERING_COMPLETE.
Proof.
  unfold ICE_GATHERING_NEW, ICE_GATHERING_GATHERING, ICE_GATHERING_COMPLETE.
  lia.
Qed.
