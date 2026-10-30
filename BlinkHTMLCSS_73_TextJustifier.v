(* Blink2Coq HTML/CSS Synthesis for TextJustifier *)
(* Source: renderer/core/layout/inline/text_justifier.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition space_per_opportunity (total_extra opps : Z) : Z :=
  if opps <=? 0 then 0 else total_extra / opps.
Theorem justified_space_conservation : forall total_extra opps,
  0 <= total_extra -> 0 < opps ->
  opps * space_per_opportunity total_extra opps <= total_extra.
Proof.
  intros total_extra opps Htot Hopps.
  unfold space_per_opportunity.
  assert (E: (opps <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  apply Z.mul_div_le. lia.
Qed.
