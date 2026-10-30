(* Blink2Coq Synthesis for InlineBreakToken *)
(* Source: third_party/blink/renderer/core/layout/inline/inline_break_token.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem hyphenation_space_sound : forall w hw av,
  0 <= hw -> w + hw <= av -> w <= av.
Proof. intros. lia. Qed.
