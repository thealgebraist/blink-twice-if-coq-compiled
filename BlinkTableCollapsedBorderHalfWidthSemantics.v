From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.6.2 Collapsed Border Half-Width Integer Allocation *)
Definition border_half_left (w : Z) : Z :=
  w / 2.

Definition border_half_right (w : Z) : Z :=
  w - (w / 2).

Theorem border_half_sum_exact : forall w,
  border_half_left w + border_half_right w = w.
Proof.
  intros w.
  unfold border_half_left, border_half_right.
  lia.
Qed.

Theorem border_half_diff_at_most_one : forall w,
  w >= 0 ->
  0 <= border_half_right w - border_half_left w <= 1.
Proof.
  intros w Hw.
  unfold border_half_left, border_half_right.
  assert (Hrem: 0 <= w mod 2 < 2) by (apply Z.mod_pos_bound; lia).
  assert (Heq: w = 2 * (w / 2) + w mod 2) by (apply Z.div_mod; lia).
  lia.
Qed.
