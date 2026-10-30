(* Blink2Coq HTML/CSS Synthesis for ColorMix *)
(* Source: renderer/core/css/color_mix.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition complement_pct (p : Z) : Z := 100 - p.
Theorem color_mix_percentage_sum : forall p,
  p + complement_pct p = 100.
Proof. intros. unfold complement_pct. lia. Qed.
