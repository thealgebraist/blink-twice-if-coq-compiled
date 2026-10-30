Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Definition resolve_flex_main_size (base free_space min_sz max_sz : Z) : Z :=
  let target := base + free_space in
  if target <? min_sz then min_sz
  else if max_sz <? target then max_sz
  else target.

Theorem resolve_flex_main_size_bounded :
  forall (base free_space min_sz max_sz : Z),
    min_sz <= max_sz ->
    min_sz <= resolve_flex_main_size base free_space min_sz max_sz <= max_sz.
Proof.
  intros base free min_sz max_sz Hle.
  unfold resolve_flex_main_size.
  destruct (base + free <? min_sz) eqn:Emin.
  - apply Z.ltb_lt in Emin. lia.
  - apply Z.ltb_ge in Emin.
    destruct (max_sz <? base + free) eqn:Emax.
    + apply Z.ltb_lt in Emax. lia.
    + apply Z.ltb_ge in Emax. lia.
Qed.
