(* Blink2Coq Synthesis for BidiParagraph *)
(* Source: third_party/blink/renderer/core/layout/inline/bidi_paragraph.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_bidi_level (lvl : Z) : Z :=
  if lvl <? 0 then 0 else if 125 <? lvl then 125 else lvl.
Theorem bidi_level_bounded : forall lvl,
  0 <= clamp_bidi_level lvl <= 125.
Proof.
  intros. unfold clamp_bidi_level.
  destruct (lvl <? 0) eqn:E1; [apply Z.ltb_lt in E1; lia | apply Z.ltb_ge in E1].
  destruct (125 <? lvl) eqn:E2; [apply Z.ltb_lt in E2; lia | apply Z.ltb_ge in E2; lia].
Qed.
