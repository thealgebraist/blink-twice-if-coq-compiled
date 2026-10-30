Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Bluetooth GATT Connection State Automaton Semantics *)
(** Web Bluetooth §4.2 GATTServer connect/disconnect state machine *)

Inductive gatt_state : Type :=
| StateDisconnected
| StateConnecting
| StateConnected
| StateDisconnecting.

Definition valid_transition (from_s to_s : gatt_state) : bool :=
  match from_s, to_s with
  | StateDisconnected, StateConnecting => true
  | StateConnecting, StateConnected => true
  | StateConnecting, StateDisconnected => true
  | StateConnected, StateDisconnecting => true
  | StateConnected, StateDisconnected => true
  | StateDisconnecting, StateDisconnected => true
  | _, _ => false
  end.

Theorem disconnected_cannot_reach_connected_directly :
  valid_transition StateDisconnected StateConnected = false.
Proof.
  reflexivity.
Qed.

Theorem disconnecting_cannot_reconnect_directly :
  valid_transition StateDisconnecting StateConnected = false.
Proof.
  reflexivity.
Qed.
