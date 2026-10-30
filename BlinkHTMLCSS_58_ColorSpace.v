(* Blink2Coq HTML/CSS Synthesis for ColorSpace *)
(* Source: renderer/platform/graphics/color_space.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_8bit (v : Z) : Z :=
  if v <? 0 then 0 else if 255 <? v then 255 else v.
Theorem clamp_8bit_bounded : forall v,
  0 <= clamp_8bit v <= 255.
Proof.
  intros. unfold clamp_8bit.
  destruct (v <? 0) eqn:E1; [apply Z.ltb_lt in E1; lia | apply Z.ltb_ge in E1].
  destruct (255 <? v) eqn:E2; [apply Z.ltb_lt in E2; lia | apply Z.ltb_ge in E2; lia].
Qed.
