Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Snap Proximity Semantics *)
(** CSS Scroll Snap 1 §6.1: snap proximity threshold check *)

Definition within_snap_proximity (s p threshold : Z) : bool :=
  Z.abs (s - p) <=? Z.max 0 threshold.

Theorem within_proximity_sound : forall s p threshold,
  within_snap_proximity s p threshold = true <-> Z.abs (s - p) <= Z.max 0 threshold.
Proof.
  intros s p threshold.
  unfold within_snap_proximity.
  apply Z.leb_le.
Qed.
