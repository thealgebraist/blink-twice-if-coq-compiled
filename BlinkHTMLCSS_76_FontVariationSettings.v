(* Blink2Coq HTML/CSS Synthesis for FontVariationSettings *)
(* Source: renderer/core/css/font_variation_settings.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_font_weight (w : Z) : Z :=
  if w <? 1 then 1 else if 1000 <? w then 1000 else w.
Theorem font_weight_bounded : forall w,
  1 <= clamp_font_weight w <= 1000.
Proof.
  intros w. unfold clamp_font_weight.
  destruct (w <? 1) eqn:E1; [apply Z.ltb_lt in E1; lia |].
  apply Z.ltb_ge in E1.
  destruct (1000 <? w) eqn:E2; [apply Z.ltb_lt in E2; lia |].
  apply Z.ltb_ge in E2; lia.
Qed.
