From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Inductive EastAsianWidthCategory : Type :=
| EA_Fullwidth
| EA_Wide
| EA_Halfwidth
| EA_Narrow
| EA_Neutral.

Definition east_asian_char_advance
  (cat : EastAsianWidthCategory) (em_unit : Z) : Z :=
  match cat with
  | EA_Fullwidth | EA_Wide => em_unit
  | EA_Halfwidth | EA_Narrow | EA_Neutral => em_unit / 2
  end.

Theorem fullwidth_is_double_halfwidth_even : forall em_unit,
  em_unit >= 0 ->
  em_unit mod 2 = 0 ->
  east_asian_char_advance EA_Fullwidth em_unit =
  2 * east_asian_char_advance EA_Halfwidth em_unit.
Proof.
  intros em_unit Hpos Hmod.
  unfold east_asian_char_advance.
  pose proof (Z.div_exact em_unit 2 ltac:(lia)) as [H1 H2].
  assert (H: em_unit = 2 * (em_unit / 2)).
  { apply H2. exact Hmod. }
  exact H.
Qed.

Theorem east_asian_advance_nonneg : forall cat em_unit,
  em_unit >= 0 ->
  east_asian_char_advance cat em_unit >= 0.
Proof.
  intros cat em_unit Hpos.
  destruct cat; unfold east_asian_char_advance; try lia.
  - assert (0 <= em_unit / 2) by (apply Z.div_pos; lia). lia.
  - assert (0 <= em_unit / 2) by (apply Z.div_pos; lia). lia.
  - assert (0 <= em_unit / 2) by (apply Z.div_pos; lia). lia.
Qed.
