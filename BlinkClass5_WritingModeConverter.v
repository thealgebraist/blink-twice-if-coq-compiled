Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Definition logical_to_physical_x (lx ly wm cw : Z) : Z :=
  if wm =? 1 then cw - ly else lx.

Definition physical_to_logical_y (px py wm cw : Z) : Z :=
  if wm =? 1 then cw - px else py.

Theorem writing_mode_vertical_rl_involution :
  forall (lx ly cw : Z),
    physical_to_logical_y (logical_to_physical_x lx ly 1 cw) 0 1 cw = ly.
Proof.
  intros lx ly cw.
  unfold logical_to_physical_x, physical_to_logical_y.
  simpl.
  ring.
Qed.
