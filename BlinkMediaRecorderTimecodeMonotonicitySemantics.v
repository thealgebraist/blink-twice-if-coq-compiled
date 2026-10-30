Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MediaRecorder Timecode Progression Semantics *)
(** MediaStream Recording §4.1: chunk timecode progression monotonicity *)

Definition advance_chunk_timecode (curr_timecode delta : Z) : Z :=
  curr_timecode + Z.max 0 delta.

Theorem chunk_timecode_monotonic : forall t d,
  t <= advance_chunk_timecode t d.
Proof.
  intros t d.
  unfold advance_chunk_timecode.
  assert (0 <= Z.max 0 d) by apply Z.le_max_l.
  lia.
Qed.
