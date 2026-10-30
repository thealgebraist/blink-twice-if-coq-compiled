Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Credit Card Luhn Checksum Algorithm Semantics *)
(** ISO/IEC 7812-1 / Luhn mod 10 formula *)

Definition luhn_double_digit (d : Z) : Z :=
  let d2 := d * 2 in
  if 9 <? d2 then d2 - 9 else d2.

Theorem luhn_double_digit_bounds : forall d,
  0 <= d <= 9 ->
  0 <= luhn_double_digit d <= 9.
Proof.
  intros d [H0 H9].
  unfold luhn_double_digit.
  destruct (9 <? d * 2) eqn:E.
  - apply Z.ltb_lt in E. lia.
  - apply Z.ltb_ge in E. lia.
Qed.
