From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §8.3.1 Negative Margin Collapsing Algebra *)
Definition collapse_margin_strut (pos_m : Z) (neg_m : Z) : Z :=
  pos_m + neg_m.

Theorem collapsed_margin_bounded : forall pos_m neg_m,
  pos_m >= 0 ->
  neg_m <= 0 ->
  neg_m <= collapse_margin_strut pos_m neg_m <= pos_m.
Proof.
  intros pos_m neg_m Hpos Hneg.
  unfold collapse_margin_strut. lia.
Qed.

Theorem collapsed_margin_zero_neg : forall pos_m,
  collapse_margin_strut pos_m 0 = pos_m.
Proof.
  intros. unfold collapse_margin_strut. lia.
Qed.
