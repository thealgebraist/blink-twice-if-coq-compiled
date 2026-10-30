Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Fraction Gap Clearance Semantics *)
(** MathML Core §3.3.2: gap clearance >= min_gap *)

Definition compute_fraction_total_gap (gap_above gap_below min_gap : Z) : Z :=
  Z.max min_gap gap_above + Z.max min_gap gap_below.

Theorem fraction_total_gap_at_least_double_min : forall ga gb min_gap,
  0 <= min_gap ->
  2 * min_gap <= compute_fraction_total_gap ga gb min_gap.
Proof.
  intros ga gb min_gap Hmin.
  unfold compute_fraction_total_gap.
  lia.
Qed.
