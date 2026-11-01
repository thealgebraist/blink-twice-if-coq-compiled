(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record SelectorIsMaxSpec := mkSelectorIsMaxSpec {
  selectorismaxspec_branch1_spec : Z;
  selectorismaxspec_branch2_spec : Z;
  selectorismaxspec_branch3_spec : Z
}.

Definition is_pseudo_max_spec3 (s1 : Z) (s2 : Z) (s3 : Z) : Z :=
  Z.max (Z.max s1 s2) s3.

Theorem is_pseudo_max_spec3_dominates_branches :
  forall (s1 s2 s3 : Z), s1 <= is_pseudo_max_spec3 s1 s2 s3 /\ s2 <= is_pseudo_max_spec3 s1 s2 s3 /\ s3 <= is_pseudo_max_spec3 s1 s2 s3.
Proof.
  intros s1 s2 s3. unfold is_pseudo_max_spec3. lia.
Qed.
