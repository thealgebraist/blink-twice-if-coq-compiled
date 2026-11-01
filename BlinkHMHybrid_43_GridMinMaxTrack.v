(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record GridMinMaxTrack := mkGridMinMaxTrack {
  gridminmaxtrack_min_track : Z;
  gridminmaxtrack_max_track : Z;
  gridminmaxtrack_avail_share : Z
}.

Definition resolve_grid_minmax (min_t : Z) (max_t : Z) (avail : Z) : Z :=
  Z.max min_t (Z.min avail max_t).

Theorem grid_minmax_never_below_min_track :
  forall (min_t max_t avail : Z), min_t <= resolve_grid_minmax min_t max_t avail.
Proof.
  intros min_t max_t avail. unfold resolve_grid_minmax. lia.
Qed.
