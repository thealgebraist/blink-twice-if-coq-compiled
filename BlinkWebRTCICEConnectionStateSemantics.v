Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebRTC ICE Connection State Semantics *)
(** WebRTC 1.0 §4.3.3: connected and completed indicate active transport *)

Definition ICE_CONN_NEW          : Z := 0.
Definition ICE_CONN_CHECKING     : Z := 1.
Definition ICE_CONN_CONNECTED    : Z := 2.
Definition ICE_CONN_COMPLETED    : Z := 3.
Definition ICE_CONN_FAILED       : Z := 4.
Definition ICE_CONN_DISCONNECTED : Z := 5.
Definition ICE_CONN_CLOSED       : Z := 6.

Definition is_active_ice_connection (st : Z) : bool :=
  (st =? ICE_CONN_CONNECTED) || (st =? ICE_CONN_COMPLETED).

Theorem connected_is_active :
  is_active_ice_connection ICE_CONN_CONNECTED = true.
Proof.
  reflexivity.
Qed.

Theorem completed_is_active :
  is_active_ice_connection ICE_CONN_COMPLETED = true.
Proof.
  reflexivity.
Qed.

Theorem failed_is_not_active :
  is_active_ice_connection ICE_CONN_FAILED = false.
Proof.
  reflexivity.
Qed.
