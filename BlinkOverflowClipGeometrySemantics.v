From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Overflow 3 §3 1D Overflow Clip Geometry *)
Definition intersect_interval (x1 r1 x2 r2 : Z) : Z * Z :=
  let left := Z.max x1 x2 in
  let right := Z.min r1 r2 in
  if left <=? right then (left, right)
  else (left, left).

Theorem intersect_interval_contained_left : forall x1 r1 x2 r2,
  let '(l, r) := intersect_interval x1 r1 x2 r2 in
  l >= x1 \/ l >= x2.
Proof.
  intros x1 r1 x2 r2.
  unfold intersect_interval.
  destruct (Z.max x1 x2 <=? Z.min r1 r2) eqn:E;
  assert (Z.max x1 x2 >= x1) by (apply Z.le_ge; apply Z.le_max_l);
  lia.
Qed.

Theorem intersect_interval_valid_range : forall x1 r1 x2 r2,
  let '(l, r) := intersect_interval x1 r1 x2 r2 in
  l <= r.
Proof.
  intros x1 r1 x2 r2.
  unfold intersect_interval.
  destruct (Z.max x1 x2 <=? Z.min r1 r2) eqn:E.
  - apply Z.leb_le in E. lia.
  - lia.
Qed.
