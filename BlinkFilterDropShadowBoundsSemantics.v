From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Filters 1 §5.4 Filter Drop-Shadow Bounds *)
Definition drop_shadow_bounds_1d (x w dx blur : Z) : Z * Z :=
  (Z.min x (x + dx - blur), Z.max (x + w) (x + dx + w + blur)).

Theorem drop_shadow_contains_original : forall x w dx blur,
  w >= 0 ->
  blur >= 0 ->
  let '(min_x, max_x) := drop_shadow_bounds_1d x w dx blur in
  min_x <= x /\ x + w <= max_x.
Proof.
  intros x w dx blur Hw Hblur.
  unfold drop_shadow_bounds_1d.
  assert (Z.min x (x + dx - blur) <= x) by (apply Z.le_min_l).
  assert (x + w <= Z.max (x + w) (x + dx + w + blur)) by (apply Z.le_max_l).
  lia.
Qed.
