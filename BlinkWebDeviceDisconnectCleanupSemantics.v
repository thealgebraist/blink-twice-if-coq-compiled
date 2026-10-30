Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Peripheral Device Disconnect Cleanup Semantics *)
(** Web Serial / WebUSB / WebHID disconnect resets session state *)

Record device_session_state : Type := mk_session {
  is_opened        : bool;
  active_transfers : Z
}.

Definition disconnect_device (s : device_session_state) : device_session_state :=
  {| is_opened := false; active_transfers := 0 |}.

Theorem disconnect_cleans_up : forall s,
  is_opened (disconnect_device s) = false /\
  active_transfers (disconnect_device s) = 0.
Proof.
  intros s.
  unfold disconnect_device.
  split; reflexivity.
Qed.
