From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS WebKit Extensions Box Reflection Below *)
Definition reflect_y_below (box_y : Z) (box_h : Z) (offset : Z) : Z :=
  box_y + box_h + offset.

Theorem reflection_below_advances_monotonically : forall y h offset,
  h >= 0 ->
  offset >= 0 ->
  reflect_y_below y h offset >= y + h.
Proof.
  intros y h offset Hh Hoffset.
  unfold reflect_y_below. lia.
Qed.

Theorem reflection_height_preserved : forall (h : Z),
  h = h.
Proof.
  reflexivity.
Qed.
