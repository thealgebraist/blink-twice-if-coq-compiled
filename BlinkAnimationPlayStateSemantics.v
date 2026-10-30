Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Animation Play State Machine Semantics *)
(** Web Animations §4.5: play state transitions *)

Inductive PlayState :=
  | PlayIdle
  | PlayRunning
  | PlayPaused
  | PlayFinished.

Definition can_pause (s : PlayState) : bool :=
  match s with
  | PlayRunning => true
  | _ => false
  end.

Definition transition_pause (s : PlayState) : PlayState :=
  if can_pause s then PlayPaused else s.

Theorem running_pauses_to_paused :
  transition_pause PlayRunning = PlayPaused.
Proof.
  unfold transition_pause, can_pause; reflexivity.
Qed.

Theorem idle_pause_invariant :
  transition_pause PlayIdle = PlayIdle.
Proof.
  unfold transition_pause, can_pause; reflexivity.
Qed.
