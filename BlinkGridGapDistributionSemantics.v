From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition grid_gap_count (n : Z) : Z :=
  if n <=? 1 then 0 else n - 1.

Definition total_gap_space (n gap : Z) : Z :=
  grid_gap_count n * gap.

Definition track_offset (start track_size gap index : Z) : Z :=
  start + index * (track_size + gap).

Theorem gap_space_nonneg : forall n gap,
  n >= 0 -> gap >= 0 -> total_gap_space n gap >= 0.
Proof.
  intros n gap Hn Hgap.
  unfold total_gap_space, grid_gap_count.
  destruct (n <=? 1) eqn:E; [lia |].
  apply Z.leb_gt in E.
  assert (0 <= n - 1) by lia.
  assert (0 <= gap) by lia.
  pose proof (Z.mul_nonneg_nonneg (n - 1) gap ltac:(lia) ltac:(lia)).
  lia.
Qed.

Theorem track_offsets_strictly_monotonic : forall start track_size gap i,
  track_size > 0 ->
  gap >= 0 ->
  track_offset start track_size gap i < track_offset start track_size gap (i + 1).
Proof.
  intros start track_size gap i Hts Hgap.
  unfold track_offset.
  assert (Hstep: (i + 1) * (track_size + gap) = i * (track_size + gap) + (track_size + gap)) by ring.
  rewrite Hstep.
  lia.
Qed.
