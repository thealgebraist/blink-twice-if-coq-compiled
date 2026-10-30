From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition next_tab_stop (cur_x tab_width : Z) : Z :=
  if tab_width <=? 0 then cur_x
  else ((cur_x / tab_width) + 1) * tab_width.

Definition tab_advance (cur_x tab_width : Z) : Z :=
  next_tab_stop cur_x tab_width - cur_x.

Theorem tab_advance_strictly_positive : forall cur_x tab_width,
  tab_width > 0 ->
  tab_advance cur_x tab_width > 0.
Proof.
  intros cur_x tab_width Htab.
  unfold tab_advance, next_tab_stop.
  assert (E: (tab_width <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  pose proof (Z.div_mod cur_x tab_width ltac:(lia)) as Hdiv.
  pose proof (Z_mod_lt cur_x tab_width ltac:(lia)) as Hmod.
  assert (Halg: ((cur_x / tab_width) + 1) * tab_width = tab_width * (cur_x / tab_width) + tab_width).
  { ring. }
  rewrite Halg.
  lia.
Qed.

Theorem tab_advance_le_tab_width : forall cur_x tab_width,
  tab_width > 0 ->
  tab_advance cur_x tab_width <= tab_width.
Proof.
  intros cur_x tab_width Htab.
  unfold tab_advance, next_tab_stop.
  assert (E: (tab_width <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  pose proof (Z.div_mod cur_x tab_width ltac:(lia)) as Hdiv.
  pose proof (Z_mod_lt cur_x tab_width ltac:(lia)) as Hmod.
  assert (Halg: ((cur_x / tab_width) + 1) * tab_width = tab_width * (cur_x / tab_width) + tab_width).
  { ring. }
  rewrite Halg.
  lia.
Qed.

Theorem next_tab_stop_is_multiple : forall cur_x tab_width,
  tab_width > 0 ->
  next_tab_stop cur_x tab_width mod tab_width = 0.
Proof.
  intros cur_x tab_width Htab.
  unfold next_tab_stop.
  assert (E: (tab_width <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  apply Z_mod_mult.
Qed.
