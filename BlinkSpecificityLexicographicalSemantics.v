From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Selectors 4 §16 Specificity Tuple Lexicographical Order *)
Record SpecificityTuple := {
  spec_a : Z;
  spec_b : Z;
  spec_c : Z
}.

Definition spec_gt (s1 s2 : SpecificityTuple) : Prop :=
  spec_a s1 > spec_a s2 \/
  (spec_a s1 = spec_a s2 /\ (spec_b s1 > spec_b s2 \/
  (spec_b s1 = spec_b s2 /\ spec_c s1 > spec_c s2))).

Theorem spec_gt_irrefl : forall s,
  ~ spec_gt s s.
Proof.
  intros [a b c] Hgt.
  unfold spec_gt in Hgt; cbn in Hgt.
  lia.
Qed.

Theorem spec_gt_asym : forall s1 s2,
  spec_gt s1 s2 ->
  ~ spec_gt s2 s1.
Proof.
  intros [a1 b1 c1] [a2 b2 c2] H1 H2.
  unfold spec_gt in *; cbn in *.
  lia.
Qed.

Theorem spec_gt_trans : forall s1 s2 s3,
  spec_gt s1 s2 ->
  spec_gt s2 s3 ->
  spec_gt s1 s3.
Proof.
  intros [a1 b1 c1] [a2 b2 c2] [a3 b3 c3] H1 H2.
  unfold spec_gt in *; cbn in *.
  lia.
Qed.
