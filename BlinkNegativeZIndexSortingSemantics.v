From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS 2.1 App E §E.2 Negative Z-Index Sorting *)
Inductive SortedNegativeZ : list Z -> Prop :=
  | SN_Nil : SortedNegativeZ nil
  | SN_Single : forall z, z < 0 -> SortedNegativeZ [z]
  | SN_Cons : forall z1 z2 zs,
      z1 < 0 ->
      z1 <= z2 ->
      SortedNegativeZ (z2 :: zs) ->
      SortedNegativeZ (z1 :: z2 :: zs).

Theorem sorted_negative_z_pairwise : forall z1 z2 zs,
  SortedNegativeZ (z1 :: z2 :: zs) ->
  z1 <= z2.
Proof.
  intros z1 z2 zs Hsort.
  inversion Hsort; subst.
  exact H3.
Qed.
