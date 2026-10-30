Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Popover Top Layer Stacking Order Semantics *)
(** HTML / CSS Position 4 §6: monotonic top layer z-order progression *)

Definition push_top_layer (cur_max_z : Z) : Z :=
  cur_max_z + 1.

Theorem popover_stacking_strictly_monotonic : forall z,
  z < push_top_layer z.
Proof.
  intros z.
  unfold push_top_layer; lia.
Qed.
