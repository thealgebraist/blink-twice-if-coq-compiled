Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebAuthn signCount Monotonicity Semantics *)
(** WebAuthn Level 3 §6.1: signCount strictly advances or initializes *)

Definition is_valid_sign_count_advance (prev_count next_count : Z) : bool :=
  (prev_count =? 0) || (prev_count <? next_count).

Theorem monotonic_sign_count_advances : forall p n,
  0 < p ->
  p < n ->
  is_valid_sign_count_advance p n = true.
Proof.
  intros p n Hp Hlt.
  unfold is_valid_sign_count_advance.
  apply orb_true_intro.
  right.
  apply Z.ltb_lt.
  exact Hlt.
Qed.
