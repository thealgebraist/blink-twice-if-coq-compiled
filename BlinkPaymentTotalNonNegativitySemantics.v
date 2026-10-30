Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Payment Total Amount Non-Negativity Semantics *)
(** Payment Request API §5.5: total.amount.value must not be negative *)

Definition is_valid_total_amount (cents : Z) : bool :=
  0 <=? cents.

Theorem total_amount_non_negative : forall cents,
  is_valid_total_amount cents = true <-> cents >= 0.
Proof.
  intros cents.
  unfold is_valid_total_amount.
  split; intro H.
  - apply Z.leb_le in H. lia.
  - apply Z.leb_le. lia.
Qed.
