From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Filters 2 Backdrop Filter Blur Outset *)
Definition backdrop_sampling_bounds (box_l box_r blur_radius : Z) : Z * Z :=
  (box_l - 3 * blur_radius, box_r + 3 * blur_radius).

Theorem backdrop_contains_layer_box : forall box_l box_r blur,
  blur >= 0 ->
  let '(s_l, s_r) := backdrop_sampling_bounds box_l box_r blur in
  s_l <= box_l /\ box_r <= s_r.
Proof.
  intros box_l box_r blur Hblur.
  unfold backdrop_sampling_bounds. lia.
Qed.

Theorem backdrop_monotonic_with_blur : forall box_l box_r b1 b2,
  0 <= b1 <= b2 ->
  let '(l1, r1) := backdrop_sampling_bounds box_l box_r b1 in
  let '(l2, r2) := backdrop_sampling_bounds box_l box_r b2 in
  l2 <= l1 /\ r1 <= r2.
Proof.
  intros box_l box_r b1 b2 [Hb1 Hb12].
  unfold backdrop_sampling_bounds. lia.
Qed.
