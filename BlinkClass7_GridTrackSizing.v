Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Definition resolve_minmax_track (avail min_t max_t : Z) : Z :=
  let effective_max := if max_t <? min_t then min_t else max_t in
  if avail <? min_t then min_t
  else if effective_max <? avail then effective_max
  else avail.

Theorem resolve_minmax_track_lower_bound :
  forall (avail min_t max_t : Z),
    min_t <= resolve_minmax_track avail min_t max_t.
Proof.
  intros avail min_t max_t.
  unfold resolve_minmax_track.
  destruct (max_t <? min_t) eqn:Emax.
  - destruct (avail <? min_t) eqn:Ea1.
    + apply Z.ltb_lt in Ea1. lia.
    + apply Z.ltb_ge in Ea1.
      destruct (min_t <? avail) eqn:Ea2; lia.
  - destruct (avail <? min_t) eqn:Eb1.
    + apply Z.ltb_lt in Eb1. lia.
    + apply Z.ltb_ge in Eb1.
      destruct (max_t <? avail) eqn:Eb2.
      * apply Z.ltb_ge in Emax. lia.
      * lia.
Qed.
