Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Snap Distance Semantics *)
(** CSS Scroll Snap 1 §6: snap distance absolute difference *)

Definition snap_distance (scroll_pos snap_pos : Z) : Z :=
  Z.abs (scroll_pos - snap_pos).

Theorem snap_distance_nonneg : forall s p,
  0 <= snap_distance s p.
Proof.
  intros s p.
  unfold snap_distance.
  apply Z.abs_nonneg.
Qed.

Theorem snap_distance_zero_iff_equal : forall s p,
  snap_distance s p = 0 <-> s = p.
Proof.
  intros s p.
  unfold snap_distance.
  split.
  - intros H.
    apply Z.abs_0_iff in H.
    lia.
  - intros ->.
    assert (p - p = 0) by lia.
    rewrite H.
    reflexivity.
Qed.
