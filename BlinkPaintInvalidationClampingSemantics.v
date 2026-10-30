From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink Paint Invalidation Rect Clamping *)
Definition clamp_invalidation_rect (d_left d_right l_left l_right : Z) : Z * Z :=
  let left := Z.max d_left l_left in
  let right := Z.min d_right l_right in
  if left <=? right then (left, right)
  else (left, left).

Theorem invalidation_contained_in_layer : forall d_l d_r l_l l_r,
  let '(i_l, i_r) := clamp_invalidation_rect d_l d_r l_l l_r in
  i_l >= l_l /\ (i_l = i_r \/ i_r <= l_r).
Proof.
  intros d_l d_r l_l l_r.
  unfold clamp_invalidation_rect.
  destruct (Z.max d_l l_l <=? Z.min d_r l_r) eqn:E.
  - assert (Z.max d_l l_l >= l_l) by (apply Z.le_ge; apply Z.le_max_r).
    assert (Z.min d_r l_r <= l_r) by (apply Z.le_min_r).
    lia.
  - assert (Z.max d_l l_l >= l_l) by (apply Z.le_ge; apply Z.le_max_r).
    lia.
Qed.
