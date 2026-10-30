From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Table 3 §2 & CSS Box Model 3 Table Wrapper Fragment Assembly *)
Record FragmentBox := {
  fb_y : Z;
  fb_height : Z
}.

Definition fragment_bottom (b : FragmentBox) : Z :=
  fb_y b + fb_height b.

Record TableWrapperAssembly := {
  twa_top_caption : FragmentBox;
  twa_grid_box : FragmentBox;
  twa_bottom_caption : FragmentBox
}.

Definition is_valid_wrapper_assembly (a : TableWrapperAssembly) : Prop :=
  fragment_bottom (twa_top_caption a) <= fb_y (twa_grid_box a) /\
  fragment_bottom (twa_grid_box a) <= fb_y (twa_bottom_caption a).

Theorem valid_assembly_transitive_y : forall a,
  is_valid_wrapper_assembly a ->
  fb_height (twa_top_caption a) >= 0 ->
  fb_height (twa_grid_box a) >= 0 ->
  fb_y (twa_top_caption a) <= fb_y (twa_bottom_caption a).
Proof.
  intros a [Htop Hbot] Htop_h Hgrid_h.
  destruct a as [top grid bot]; cbn in *.
  unfold fragment_bottom in *.
  lia.
Qed.
