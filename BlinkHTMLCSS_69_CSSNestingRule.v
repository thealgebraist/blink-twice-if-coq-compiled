(* Blink2Coq HTML/CSS Synthesis for CSSNestingRule *)
(* Source: renderer/core/css/css_nesting_rule.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Record SpecificityTriple := mkSpec { spec_a : Z; spec_b : Z; spec_c : Z }.
Definition add_spec (s1 s2 : SpecificityTriple) : SpecificityTriple :=
  mkSpec (spec_a s1 + spec_a s2) (spec_b s1 + spec_b s2) (spec_c s1 + spec_c s2).
Theorem nesting_specificity_commutative : forall s1 s2,
  add_spec s1 s2 = add_spec s2 s1.
Proof.
  intros [a1 b1 c1] [a2 b2 c2]. unfold add_spec. simpl.
  rewrite (Z.add_comm a1 a2), (Z.add_comm b1 b2), (Z.add_comm c1 c2). reflexivity.
Qed.
