Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Credit Card Expiry Normalization Semantics *)
(** Autofill credit card expiration month and year expansion *)

Definition normalize_expiry_year (yy : Z) : Z :=
  if yy <? 100 then 2000 + yy else yy.

Definition is_valid_expiry_month (m : Z) : bool :=
  (1 <=? m) && (m <=? 12).

Theorem expiry_year_2digit_expansion : forall yy,
  0 <= yy < 100 ->
  normalize_expiry_year yy = 2000 + yy /\ 2000 <= normalize_expiry_year yy < 2100.
Proof.
  intros yy [H0 H1].
  unfold normalize_expiry_year.
  assert (E: (yy <? 100) = true).
  { apply Z.ltb_lt. exact H1. }
  rewrite E.
  split; lia.
Qed.

Theorem expiry_month_sound : forall m,
  is_valid_expiry_month m = true ->
  1 <= m <= 12.
Proof.
  intros m H.
  unfold is_valid_expiry_month in H.
  apply andb_prop in H.
  destruct H as [H1 H12].
  apply Z.leb_le in H1.
  apply Z.leb_le in H12.
  split; assumption.
Qed.
