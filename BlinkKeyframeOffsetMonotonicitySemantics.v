From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* Web Animations §5.3.1 Keyframe Offset Monotonicity *)
Inductive SortedKeyframeOffsets : list Z -> Prop :=
  | SKO_Nil : SortedKeyframeOffsets nil
  | SKO_Single : forall off, 0 <= off <= 1000 -> SortedKeyframeOffsets [off]
  | SKO_Cons : forall o1 o2 os,
      0 <= o1 <= 1000 ->
      o1 <= o2 ->
      SortedKeyframeOffsets (o2 :: os) ->
      SortedKeyframeOffsets (o1 :: o2 :: os).

Theorem keyframe_offsets_pairwise_monotonic : forall o1 o2 os,
  SortedKeyframeOffsets (o1 :: o2 :: os) ->
  o1 <= o2.
Proof.
  intros o1 o2 os Hsort.
  inversion Hsort; subst.
  exact H3.
Qed.
