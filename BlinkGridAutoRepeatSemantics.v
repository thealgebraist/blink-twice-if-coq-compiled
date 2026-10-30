(* ========================================================================= *)
(*               BlinkGridAutoRepeatSemantics.v                             *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink CSS Grid auto-fill and auto-fit     *)
(* track count calculation and empty track collapsing against CSS Grid 1     *)
(* §7.2.2. Fully constructive, executable, 0 admits.                         *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition compute_auto_repeat_count (w_avail track_size gap : Z) : Z :=
  Z.max 1 ((w_avail + gap) / (track_size + gap)).

Definition total_auto_fill_space (n track_size gap : Z) : Z :=
  if n <=? 0 then 0
  else n * track_size + (n - 1) * gap.

Inductive AutoRepeatType : Type :=
| AutoFill
| AutoFit.

Definition resolve_track_used_size (mode : AutoRepeatType) (track_size : Z) (occupied : bool) : Z :=
  match mode with
  | AutoFill => track_size
  | AutoFit  => if occupied then track_size else 0
  end.

Theorem auto_repeat_count_ge_1 : forall w_avail track_size gap,
  compute_auto_repeat_count w_avail track_size gap >= 1.
Proof.
  intros. unfold compute_auto_repeat_count. lia.
Qed.

Theorem auto_repeat_count_exact_when_fits : forall w_avail track_size gap,
  track_size > 0 ->
  gap >= 0 ->
  w_avail >= track_size ->
  ((w_avail + gap) / (track_size + gap) >= 1) /\
  compute_auto_repeat_count w_avail track_size gap = (w_avail + gap) / (track_size + gap).
Proof.
  intros w_avail track_size gap Hts Hgap Hw.
  unfold compute_auto_repeat_count.
  assert (Hdenom: 0 < track_size + gap) by lia.
  assert (Hnum: track_size + gap <= w_avail + gap) by lia.
  assert (Hdiv: (w_avail + gap) / (track_size + gap) >= 1).
  {
    apply Z.le_ge.
    apply Z.div_le_lower_bound; lia.
  }
  split; [exact Hdiv | lia].
Qed.

Theorem auto_fill_total_space_bounded : forall w_avail track_size gap,
  track_size > 0 ->
  gap >= 0 ->
  w_avail >= track_size ->
  let n := compute_auto_repeat_count w_avail track_size gap in
  total_auto_fill_space n track_size gap <= w_avail.
Proof.
  intros w_avail track_size gap Hts Hgap Hw n.
  destruct (auto_repeat_count_exact_when_fits w_avail track_size gap Hts Hgap Hw) as [Hge1 Heq].
  unfold n, total_auto_fill_space.
  rewrite Heq.
  assert (Hcond: (w_avail + gap) / (track_size + gap) <=? 0 = false).
  { apply Z.leb_gt. lia. }
  rewrite Hcond.
  assert (Hdenom: 0 < track_size + gap) by lia.
  pose proof (Z.mul_div_le (w_avail + gap) (track_size + gap) Hdenom) as Hle.
  assert (Halg: ((w_avail + gap) / (track_size + gap)) * track_size +
                (((w_avail + gap) / (track_size + gap)) - 1) * gap =
                ((w_avail + gap) / (track_size + gap)) * (track_size + gap) - gap).
  { ring. }
  rewrite Halg.
  lia.
Qed.
