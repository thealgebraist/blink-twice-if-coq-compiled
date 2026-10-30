From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink Cull Rect Geometry & Skipping *)
Definition is_item_culled (item_left item_right cull_left cull_right : Z) : bool :=
  (item_right <? cull_left) || (cull_right <? item_left).

Theorem item_disjoint_left_is_culled : forall item_l item_r cull_l cull_r,
  item_r < cull_l ->
  is_item_culled item_l item_r cull_l cull_r = true.
Proof.
  intros item_l item_r cull_l cull_r Hlt.
  unfold is_item_culled.
  apply Z.ltb_lt in Hlt.
  rewrite Hlt. cbn. reflexivity.
Qed.

Theorem item_disjoint_right_is_culled : forall item_l item_r cull_l cull_r,
  cull_r < item_l ->
  is_item_culled item_l item_r cull_l cull_r = true.
Proof.
  intros item_l item_r cull_l cull_r Hlt.
  unfold is_item_culled.
  apply Z.ltb_lt in Hlt.
  rewrite Hlt.
  destruct (item_r <? cull_l); reflexivity.
Qed.
