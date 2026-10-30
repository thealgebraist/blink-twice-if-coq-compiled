Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Table Tfoot Pagination Reservation Semantics *)
(** CSS Table 3 §8: repeated table footer space reservation *)

Definition reserve_tfoot_space (available_height tfoot_height : Z) : Z :=
  Z.max 0 (available_height - Z.max 0 tfoot_height).

Theorem tfoot_reservation_bounded : forall avail tf,
  0 <= avail ->
  reserve_tfoot_space avail tf <= avail.
Proof.
  intros avail tf Havail.
  unfold reserve_tfoot_space; lia.
Qed.

Theorem tfoot_reservation_nonneg : forall avail tf,
  0 <= reserve_tfoot_space avail tf.
Proof.
  intros avail tf.
  unfold reserve_tfoot_space; lia.
Qed.
