Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Event Dispatch 3-Phase Progression Semantics *)
(** DOM Standard §2.9: CAPTURING(1) -> AT_TARGET(2) -> BUBBLING(3) *)

Inductive EventPhase :=
  | PhaseCapturing
  | PhaseAtTarget
  | PhaseBubbling.

Definition phase_num (p : EventPhase) : Z :=
  match p with
  | PhaseCapturing => 1
  | PhaseAtTarget => 2
  | PhaseBubbling => 3
  end.

Theorem capture_precedes_target :
  phase_num PhaseCapturing < phase_num PhaseAtTarget.
Proof.
  unfold phase_num; lia.
Qed.

Theorem target_precedes_bubble :
  phase_num PhaseAtTarget < phase_num PhaseBubbling.
Proof.
  unfold phase_num; lia.
Qed.
