Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Grid Track Sizing MinMax Resolution Semantics *)
(** CSS Grid Layout 1 §11.4: minmax(min, max) sizing resolution *)

Definition resolve_minmax_track (avail min_track max_track : Z) : Z :=
  Z.max min_track (Z.min avail max_track).

Theorem minmax_track_bounds : forall avail min_t max_t,
  min_t <= max_t ->
  min_t <= resolve_minmax_track avail min_t max_t.
Proof.
  intros avail min_t max_t Hle.
  unfold resolve_minmax_track.
  apply Z.le_max_l.
Qed.
