Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink View Timeline Crossing Progress Semantics *)
(** Scroll-driven Animations 1 §3.5: range progress ordering *)

Definition clamp_phase_progress (prog : Z) : Z :=
  Z.max 0 (Z.min 1000 prog).

Theorem phase_progress_monotonic : forall p1 p2,
  p1 <= p2 ->
  clamp_phase_progress p1 <= clamp_phase_progress p2.
Proof.
  intros p1 p2 Hle.
  unfold clamp_phase_progress.
  lia.
Qed.
