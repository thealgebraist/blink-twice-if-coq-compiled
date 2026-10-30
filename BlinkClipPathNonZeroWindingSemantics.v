From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* SVG 2 §13.4.2 & CSS Masking 1 Non-Zero Winding Rule *)
Definition is_point_inside_non_zero (winding_number : Z) : bool :=
  negb (winding_number =? 0).

Theorem zero_winding_is_outside :
  is_point_inside_non_zero 0 = false.
Proof.
  unfold is_point_inside_non_zero. cbn. reflexivity.
Qed.

Theorem positive_winding_is_inside : forall w,
  w > 0 ->
  is_point_inside_non_zero w = true.
Proof.
  intros w Hpos.
  unfold is_point_inside_non_zero.
  destruct (w =? 0) eqn:E.
  - apply Z.eqb_eq in E. lia.
  - reflexivity.
Qed.

Theorem negative_winding_is_inside : forall w,
  w < 0 ->
  is_point_inside_non_zero w = true.
Proof.
  intros w Hneg.
  unfold is_point_inside_non_zero.
  destruct (w =? 0) eqn:E.
  - apply Z.eqb_eq in E. lia.
  - reflexivity.
Qed.
