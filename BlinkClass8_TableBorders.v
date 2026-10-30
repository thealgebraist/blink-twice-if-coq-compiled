Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Definition compute_border_priority (style width : Z) : Z :=
  if style =? 3 then 100000 (* Hidden *)
  else width * 10 + style.

Theorem hidden_border_dominates_all :
  forall (w_other s_other : Z),
    0 <= w_other < 1000 ->
    0 <= s_other <= 2 ->
    compute_border_priority 3 0 > compute_border_priority s_other w_other.
Proof.
  intros w_other s_other Hw Hs.
  unfold compute_border_priority.
  simpl.
  destruct (s_other =? 3) eqn:Es.
  - apply Z.eqb_eq in Es. lia.
  - lia.
Qed.
