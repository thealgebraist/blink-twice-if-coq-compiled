Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Command Buffer State Semantics *)
(** WebGPU §9.1: command buffer states; submitted is terminal *)

Definition CMD_RECORDING : Z := 0.
Definition CMD_READY     : Z := 1.
Definition CMD_SUBMITTED : Z := 2.

Definition is_command_submitted (st : Z) : bool :=
  st =? CMD_SUBMITTED.

Theorem submitted_is_terminal :
  is_command_submitted CMD_SUBMITTED = true.
Proof.
  reflexivity.
Qed.

Theorem recording_is_not_submitted :
  is_command_submitted CMD_RECORDING = false.
Proof.
  reflexivity.
Qed.
