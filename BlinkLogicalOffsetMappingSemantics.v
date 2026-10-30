From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Inductive WritingMode : Type :=
| H_TB
| V_LR
| V_RL.

Definition logical_to_physical_x
  (wm : WritingMode) (inline_off block_off outer_w box_w : Z) : Z :=
  match wm with
  | H_TB => inline_off
  | V_LR => block_off
  | V_RL => outer_w - (block_off + box_w)
  end.

Definition logical_to_physical_y
  (wm : WritingMode) (inline_off block_off : Z) : Z :=
  match wm with
  | H_TB => block_off
  | V_LR | V_RL => inline_off
  end.

Theorem physical_x_h_tb_matches_inline : forall i b ow bw,
  logical_to_physical_x H_TB i b ow bw = i.
Proof.
  intros. reflexivity.
Qed.

Theorem physical_y_h_tb_matches_block : forall i b,
  logical_to_physical_y H_TB i b = b.
Proof.
  intros. reflexivity.
Qed.

Theorem physical_x_v_rl_in_bounds : forall i b ow bw,
  0 <= b ->
  0 <= bw ->
  b + bw <= ow ->
  0 <= logical_to_physical_x V_RL i b ow bw <= ow.
Proof.
  intros i b ow bw H1 H2 H3.
  unfold logical_to_physical_x. lia.
Qed.
