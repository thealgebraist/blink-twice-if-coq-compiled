From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS 2.1 App E §E.2 Positive Z-Index Sorting *)
Inductive SortedPositiveZ : list Z -> Prop :=
  | SP_Nil : SortedPositiveZ nil
  | SP_Single : forall z, z > 0 -> SortedPositiveZ [z]
  | SP_Cons : forall z1 z2 zs,
      z1 > 0 ->
      z1 <= z2 ->
      SortedPositiveZ (z2 :: zs) ->
      SortedPositiveZ (z1 :: z2 :: zs).

Theorem sorted_positive_z_pairwise : forall z1 z2 zs,
  SortedPositiveZ (z1 :: z2 :: zs) ->
  z1 <= z2.
Proof.
  intros z1 z2 zs Hsort.
  inversion Hsort; subst.
  exact H3.
Qed.
