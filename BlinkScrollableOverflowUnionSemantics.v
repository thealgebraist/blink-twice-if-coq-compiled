From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Overflow 3 §3 Scrollable Overflow Accumulation *)
Definition union_overflow_1d (bb_l bb_r ch_l ch_r : Z) : Z * Z :=
  (Z.min bb_l ch_l, Z.max bb_r ch_r).

Theorem overflow_contains_border_box : forall bb_l bb_r ch_l ch_r,
  let '(ol, or) := union_overflow_1d bb_l bb_r ch_l ch_r in
  ol <= bb_l /\ bb_r <= or.
Proof.
  intros bb_l bb_r ch_l ch_r.
  unfold union_overflow_1d.
  assert (Z.min bb_l ch_l <= bb_l) by (apply Z.le_min_l).
  assert (bb_r <= Z.max bb_r ch_r) by (apply Z.le_max_l).
  lia.
Qed.

Theorem overflow_contains_child : forall bb_l bb_r ch_l ch_r,
  let '(ol, or) := union_overflow_1d bb_l bb_r ch_l ch_r in
  ol <= ch_l /\ ch_r <= or.
Proof.
  intros bb_l bb_r ch_l ch_r.
  unfold union_overflow_1d.
  assert (Z.min bb_l ch_l <= ch_l) by (apply Z.le_min_r).
  assert (ch_r <= Z.max bb_r ch_r) by (apply Z.le_max_r).
  lia.
Qed.
