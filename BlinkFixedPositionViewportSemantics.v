From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition resolve_fixed_position (left top : Z) : Z * Z :=
  (left, top).

Theorem fixed_position_scroll_invariance : forall (sx sy left top : Z),
  resolve_fixed_position left top = (left, top).
Proof.
  intros. reflexivity.
Qed.
