Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record LayoutUnit := mkLayoutUnit {
  lu_value : Z
}.

Definition layout_unit_clamp (v lo hi : Z) : Z :=
  if v <? lo then lo
  else if hi <? v then hi
  else v.

Theorem layout_unit_clamp_bounded :
  forall (v lo hi : Z),
    lo <= hi ->
    lo <= layout_unit_clamp v lo hi <= hi.
Proof.
  intros v lo hi Hle.
  unfold layout_unit_clamp.
  destruct (v <? lo) eqn:Elo.
  - apply Z.ltb_lt in Elo. lia.
  - apply Z.ltb_ge in Elo.
    destruct (hi <? v) eqn:Ehi.
    + apply Z.ltb_lt in Ehi. lia.
    + apply Z.ltb_ge in Ehi. lia.
Qed.
