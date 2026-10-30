Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn AbortSignal Cancellation Semantics *)
(** WebAuthn Level 3 §5.1.3: abort signal triggers rejection *)

Definition SIGNAL_ACTIVE  : Z := 0.
Definition SIGNAL_ABORTED : Z := 1.

Definition is_operation_aborted (signal_state : Z) : bool :=
  signal_state =? SIGNAL_ABORTED.

Theorem aborted_signal_detected :
  is_operation_aborted SIGNAL_ABORTED = true.
Proof.
  reflexivity.
Qed.

Theorem active_signal_not_aborted :
  is_operation_aborted SIGNAL_ACTIVE = false.
Proof.
  reflexivity.
Qed.
