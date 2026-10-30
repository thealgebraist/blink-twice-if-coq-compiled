From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Sizing 3 §5.2 Replaced Element Aspect Ratio *)
Definition compute_replaced_height (w : Z) (ratio_w : Z) (ratio_h : Z) : Z :=
  if ratio_w <=? 0 then 0
  else (w * ratio_h) / ratio_w.

Theorem replaced_height_nonneg : forall w rw rh,
  w >= 0 ->
  rw > 0 ->
  rh >= 0 ->
  compute_replaced_height w rw rh >= 0.
Proof.
  intros w rw rh Hw Hrw Hrh.
  unfold compute_replaced_height.
  destruct (rw <=? 0) eqn:E.
  - apply Z.leb_le in E. lia.
  - assert (0 <= (w * rh) / rw).
    { apply Z.div_le_lower_bound; lia. }
    lia.
Qed.

Theorem replaced_height_monotonic : forall w1 w2 rw rh,
  0 <= w1 <= w2 ->
  rw > 0 ->
  rh >= 0 ->
  compute_replaced_height w1 rw rh <= compute_replaced_height w2 rw rh.
Proof.
  intros w1 w2 rw rh [Hw1 Hw12] Hrw Hrh.
  unfold compute_replaced_height.
  destruct (rw <=? 0) eqn:E.
  - apply Z.leb_le in E. lia.
  - assert (Hmul: w1 * rh <= w2 * rh) by (apply Z.mul_le_mono_nonneg_r; lia).
    apply Z.div_le_mono; lia.
Qed.
