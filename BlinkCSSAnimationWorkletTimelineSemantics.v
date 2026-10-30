Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Animation Worklet Timeline Progress Semantics *)
(** CSS Animation Worklet 1 §2: timeline fraction clamping within [0, 1000] *)

Definition clamp_timeline_fraction (current total : Z) : Z :=
  if total <=? 0 then 0
  else Z.max 0 (Z.min 1000 ((current * 1000) / total)).

Theorem timeline_fraction_bounded : forall c tot,
  0 < tot ->
  0 <= clamp_timeline_fraction c tot <= 1000.
Proof.
  intros c tot Htot.
  unfold clamp_timeline_fraction.
  destruct (tot <=? 0) eqn:Heq.
  - apply Z.leb_le in Heq; lia.
  - lia.
Qed.
