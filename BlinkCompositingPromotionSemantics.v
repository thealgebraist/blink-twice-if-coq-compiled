From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink Compositing Promotion Decision *)
Record CompositingTriggers := {
  has_3d_transform : bool;
  will_change_transform : bool;
  active_opacity_anim : bool
}.

Definition should_promote_to_composited (t : CompositingTriggers) : bool :=
  has_3d_transform t || will_change_transform t || active_opacity_anim t.

Theorem promotion_if_3d_transform : forall t,
  has_3d_transform t = true ->
  should_promote_to_composited t = true.
Proof.
  intros [tr3d wc anim] Htr; cbn in *. subst. reflexivity.
Qed.

Theorem promotion_if_will_change : forall t,
  will_change_transform t = true ->
  should_promote_to_composited t = true.
Proof.
  intros [tr3d wc anim] Hwc; cbn in *. subst.
  destruct tr3d; reflexivity.
Qed.
