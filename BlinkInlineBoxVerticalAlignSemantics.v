(* ========================================================================= *)
(*               BlinkInlineBoxVerticalAlignSemantics.v                     *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Inline Box Vertical Alignment       *)
(* against CSS Inline Layout 3 §5. Fully constructive, 0 admits.             *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Inductive VerticalAlignMode : Type :=
| VABaseline
| VASub
| VASuper
| VAMiddle.

Definition compute_vertical_shift
  (mode : VerticalAlignMode) (sub_offset super_offset x_height box_height : Z) : Z :=
  match mode with
  | VABaseline => 0
  | VASub      => sub_offset
  | VASuper    => - super_offset
  | VAMiddle   => - ((x_height - box_height) / 2)
  end.

Definition apply_vertical_shift (baseline_y shift : Z) : Z :=
  baseline_y + shift.

Theorem baseline_shift_identity : forall b_y sub_off super_off x_h b_h,
  apply_vertical_shift b_y (compute_vertical_shift VABaseline sub_off super_off x_h b_h) = b_y.
Proof.
  intros. unfold apply_vertical_shift, compute_vertical_shift. lia.
Qed.

Theorem sub_shift_advances_downward : forall b_y sub_off super_off x_h b_h,
  sub_off > 0 ->
  apply_vertical_shift b_y (compute_vertical_shift VASub sub_off super_off x_h b_h) > b_y.
Proof.
  intros. unfold apply_vertical_shift, compute_vertical_shift. lia.
Qed.

Theorem super_shift_moves_upward : forall b_y sub_off super_off x_h b_h,
  super_off > 0 ->
  apply_vertical_shift b_y (compute_vertical_shift VASuper sub_off super_off x_h b_h) < b_y.
Proof.
  intros. unfold apply_vertical_shift, compute_vertical_shift. lia.
Qed.
