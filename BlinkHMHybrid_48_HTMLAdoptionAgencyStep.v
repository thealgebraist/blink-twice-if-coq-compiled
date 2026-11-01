(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLAdoptionAgencyStep := mkHTMLAdoptionAgencyStep {
  htmladoptionagencystep_outer_fuel : Z;
  htmladoptionagencystep_inner_fuel : Z
}.

Definition aaa_lex_measure (outer_rem : Z) (inner_rem : Z) : Z :=
  4 * outer_rem + inner_rem.

Theorem aaa_lex_measure_strictly_decreases :
  forall (outer_rem inner_rem : Z), 1 <= outer_rem <= 8 -> 0 <= inner_rem <= 3 -> (1 <= inner_rem -> aaa_lex_measure outer_rem (inner_rem - 1) < aaa_lex_measure outer_rem inner_rem) /\ (aaa_lex_measure (outer_rem - 1) 3 < aaa_lex_measure outer_rem 0).
Proof.
  intros outer_rem inner_rem Ho Hi. unfold aaa_lex_measure. lia.
Qed.
