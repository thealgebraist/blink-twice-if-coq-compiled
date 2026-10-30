From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Writing Modes 3 §4 Logical to Physical Box Strut Mapping *)
Record LogicalBoxStrut := {
  lbs_inline_start : Z;
  lbs_inline_end : Z;
  lbs_block_start : Z;
  lbs_block_end : Z
}.

Record PhysicalBoxStrut := {
  pbs_top : Z;
  pbs_right : Z;
  pbs_bottom : Z;
  pbs_left : Z
}.

Definition map_strut_horizontal_tb (s : LogicalBoxStrut) : PhysicalBoxStrut :=
  {| pbs_top := lbs_block_start s;
     pbs_bottom := lbs_block_end s;
     pbs_left := lbs_inline_start s;
     pbs_right := lbs_inline_end s |}.

Theorem strut_horizontal_tb_inline_sum_conserved : forall s,
  pbs_left (map_strut_horizontal_tb s) + pbs_right (map_strut_horizontal_tb s) =
  lbs_inline_start s + lbs_inline_end s.
Proof.
  intros [ins ie bs be]; cbn. reflexivity.
Qed.

Theorem strut_horizontal_tb_block_sum_conserved : forall s,
  pbs_top (map_strut_horizontal_tb s) + pbs_bottom (map_strut_horizontal_tb s) =
  lbs_block_start s + lbs_block_end s.
Proof.
  intros [ins ie bs be]; cbn. reflexivity.
Qed.
