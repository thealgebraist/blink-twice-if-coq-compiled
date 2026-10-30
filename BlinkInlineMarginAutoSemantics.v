From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.3.3 Inline Auto Margin Distribution *)
Definition compute_inline_auto_margin (cb_w : Z) (used_w : Z) : Z :=
  if cb_w <=? used_w then 0
  else (cb_w - used_w) / 2.

Theorem auto_margin_nonneg : forall cb_w used_w,
  compute_inline_auto_margin cb_w used_w >= 0.
Proof.
  intros cb_w used_w.
  unfold compute_inline_auto_margin.
  destruct (cb_w <=? used_w) eqn:E.
  - lia.
  - apply Z.leb_gt in E.
    assert (0 <= (cb_w - used_w) / 2).
    { apply Z.div_le_lower_bound; lia. }
    lia.
Qed.

Theorem auto_margins_fit : forall cb_w used_w,
  used_w >= 0 ->
  compute_inline_auto_margin cb_w used_w + used_w + compute_inline_auto_margin cb_w used_w <= Z.max cb_w used_w.
Proof.
  intros cb_w used_w Hu.
  unfold compute_inline_auto_margin.
  destruct (cb_w <=? used_w) eqn:E.
  - apply Z.leb_le in E. lia.
  - apply Z.leb_gt in E.
    assert (Hdiv: 2 * ((cb_w - used_w) / 2) <= cb_w - used_w).
    { assert (Hrem: 0 <= (cb_w - used_w) mod 2 < 2) by (apply Z.mod_pos_bound; lia).
      assert (Heq: (cb_w - used_w) = 2 * ((cb_w - used_w) / 2) + (cb_w - used_w) mod 2) by (apply Z.div_mod; lia).
      lia. }
    lia.
Qed.
