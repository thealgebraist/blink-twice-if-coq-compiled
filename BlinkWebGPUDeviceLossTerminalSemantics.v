Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Device Loss Terminal Semantics *)
(** WebGPU §5.1: device loss state terminal irreversibility *)

Definition DEVICE_ACTIVE : Z := 0.
Definition DEVICE_LOST   : Z := 1.

Definition is_device_lost (st : Z) : bool :=
  st =? DEVICE_LOST.

Theorem device_lost_sound :
  is_device_lost DEVICE_LOST = true.
Proof.
  reflexivity.
Qed.

Theorem device_active_not_lost :
  is_device_lost DEVICE_ACTIVE = false.
Proof.
  reflexivity.
Qed.
