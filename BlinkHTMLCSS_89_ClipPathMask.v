(* Blink2Coq HTML/CSS Synthesis for ClipPathMask *)
(* Source: renderer/core/paint/clip_path_mask.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_alpha (a : Z) : Z :=
  if a <? 0 then 0 else if 255 <? a then 255 else a.
Theorem alpha_mask_bounds : forall a,
  0 <= clamp_alpha a <= 255.
Proof.
  intros a. unfold clamp_alpha.
  destruct (a <? 0) eqn:E1; [apply Z.ltb_lt in E1; lia |].
  apply Z.ltb_ge in E1.
  destruct (255 <? a) eqn:E2; [apply Z.ltb_lt in E2; lia |].
  apply Z.ltb_ge in E2; lia.
Qed.
