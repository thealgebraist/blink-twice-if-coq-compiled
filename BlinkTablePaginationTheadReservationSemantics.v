Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Table Thead Pagination Reservation Semantics *)
(** CSS Table 3 §8: repeated table header space reservation *)

Definition reserve_thead_space (available_height thead_height : Z) : Z :=
  Z.max 0 (available_height - Z.max 0 thead_height).

Theorem thead_reservation_bounded : forall avail th,
  0 <= avail ->
  reserve_thead_space avail th <= avail.
Proof.
  intros avail th Havail.
  unfold reserve_thead_space; lia.
Qed.

Theorem thead_reservation_nonneg : forall avail th,
  0 <= reserve_thead_space avail th.
Proof.
  intros avail th.
  unfold reserve_thead_space; lia.
Qed.
