Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Position Try Coordinate Flip Reflection Semantics *)
(** CSS Anchor Positioning §4: flip-block/flip-inline reflection involution *)

Definition flip_coordinate (container_size target_size coord : Z) : Z :=
  container_size - coord - target_size.

Theorem flip_coordinate_involutive : forall C S x,
  flip_coordinate C S (flip_coordinate C S x) = x.
Proof.
  intros C S x.
  unfold flip_coordinate; lia.
Qed.
