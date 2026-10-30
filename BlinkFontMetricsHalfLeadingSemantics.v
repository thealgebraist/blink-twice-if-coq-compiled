From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition half_leading (line_height ascent descent : Z) : Z :=
  (line_height - (ascent + descent)) / 2.

Definition effective_ascent (line_height ascent descent : Z) : Z :=
  ascent + half_leading line_height ascent descent.

Definition effective_descent (line_height ascent descent : Z) : Z :=
  line_height - effective_ascent line_height ascent descent.

Theorem half_leading_exact_line_height : forall line_height ascent descent,
  effective_ascent line_height ascent descent +
  effective_descent line_height ascent descent = line_height.
Proof.
  intros. unfold effective_descent. lia.
Qed.

Theorem half_leading_symmetric_when_even : forall line_height ascent descent,
  (line_height - (ascent + descent)) mod 2 = 0 ->
  effective_descent line_height ascent descent =
  descent + half_leading line_height ascent descent.
Proof.
  intros line_height ascent descent Hmod.
  unfold effective_descent, effective_ascent, half_leading.
  pose proof (Z.div_exact (line_height - (ascent + descent)) 2 ltac:(lia)) as [H1 H2].
  assert (H: line_height - (ascent + descent) = 2 * ((line_height - (ascent + descent)) / 2)).
  { apply H2. exact Hmod. }
  lia.
Qed.
