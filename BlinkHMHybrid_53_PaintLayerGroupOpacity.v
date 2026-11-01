(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record PaintLayerGroupOpacity := mkPaintLayerGroupOpacity {
  paintlayergroupopacity_pixel_alpha : Z;
  paintlayergroupopacity_group_opacity : Z
}.

Definition scale_group_alpha (src_a : Z) (grp_op : Z) : Z :=
  (src_a * grp_op) / 255.

Theorem scale_group_alpha_attenuates_both :
  forall (src_a grp_op : Z), 0 <= src_a <= 255 -> 0 <= grp_op <= 255 -> 0 <= scale_group_alpha src_a grp_op /\ scale_group_alpha src_a grp_op <= src_a /\ scale_group_alpha src_a grp_op <= grp_op.
Proof.
  intros src_a grp_op Hs Hg. unfold scale_group_alpha. split; [| split].
  - apply Z.div_pos; [nia | lia].
  - apply Z.div_le_upper_bound; [lia | nia].
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.
