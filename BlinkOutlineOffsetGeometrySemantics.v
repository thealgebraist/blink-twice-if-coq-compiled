From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §18.4 Outline Geometry *)
Definition outline_bounds (box_l box_r w offset : Z) : Z * Z :=
  (box_l - (w + offset), box_r + (w + offset)).

Theorem outline_contains_border_box : forall l r w offset,
  w >= 0 ->
  offset >= 0 ->
  let '(ol, or) := outline_bounds l r w offset in
  ol <= l /\ r <= or.
Proof.
  intros l r w offset Hw Hoffset.
  unfold outline_bounds. lia.
Qed.
