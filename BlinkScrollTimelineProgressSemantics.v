(* ========================================================================= *)
(*               BlinkScrollTimelineProgressSemantics.v                      *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Scroll-Driven Animations &         *)
(* Timeline Progress per W3C CSS Scroll-driven Animations Level 1 §3.       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition scroll_timeline_progress (current_offset start_offset end_offset : Z) : Z :=
  let range := end_offset - start_offset in
  if range <=? 0 then 0
  else if current_offset <=? start_offset then 0
  else if end_offset <=? current_offset then 1000
  else ((current_offset - start_offset) * 1000) / range.

Theorem scroll_progress_at_or_before_start : forall s start_s end_s,
  s <= start_s ->
  scroll_timeline_progress s start_s end_s = 0.
Proof.
  intros s start_s end_s Hle.
  unfold scroll_timeline_progress.
  destruct (end_s - start_s <=? 0) eqn:Hrange; [reflexivity |].
  assert (s <=? start_s = true) by (apply Z.leb_le; lia).
  rewrite H.
  reflexivity.
Qed.

Theorem scroll_progress_at_or_after_end : forall s start_s end_s,
  start_s < end_s ->
  end_s <= s ->
  scroll_timeline_progress s start_s end_s = 1000.
Proof.
  intros s start_s end_s Hrange Hle.
  unfold scroll_timeline_progress.
  assert (Hpos: end_s - start_s <=? 0 = false) by (apply Z.leb_gt; lia).
  rewrite Hpos.
  assert (Hgt: s <=? start_s = false) by (apply Z.leb_gt; lia).
  rewrite Hgt.
  assert (Hend: end_s <=? s = true) by (apply Z.leb_le; lia).
  rewrite Hend.
  reflexivity.
Qed.

Theorem scroll_progress_bounds : forall s start_s end_s,
  0 <= scroll_timeline_progress s start_s end_s <= 1000.
Proof.
  intros s start_s end_s.
  unfold scroll_timeline_progress.
  destruct (end_s - start_s <=? 0) eqn:Hr; [lia |].
  destruct (s <=? start_s) eqn:Hstart; [lia |].
  destruct (end_s <=? s) eqn:Hend; [lia |].
  apply Z.leb_gt in Hr.
  apply Z.leb_gt in Hstart.
  apply Z.leb_gt in Hend.
  assert (Hnum_pos: (s - start_s) * 1000 >= 0) by nia.
  assert (Hnum_max: (s - start_s) * 1000 <= 1000 * (end_s - start_s)) by nia.
  split.
  - apply Z.div_pos; lia.
  - apply Z.div_le_upper_bound; lia.
Qed.

Theorem scroll_progress_monotonic : forall s1 s2 start_s end_s,
  s1 <= s2 ->
  scroll_timeline_progress s1 start_s end_s <= scroll_timeline_progress s2 start_s end_s.
Proof.
  intros s1 s2 start_s end_s Hle.
  unfold scroll_timeline_progress.
  destruct (end_s - start_s <=? 0) eqn:Hr; [lia |].
  apply Z.leb_gt in Hr.
  destruct (s1 <=? start_s) eqn:Hs1_start.
  - apply Z.leb_le in Hs1_start.
    destruct (s2 <=? start_s) eqn:Hs2_start; [lia |].
    destruct (end_s <=? s2) eqn:Hs2_end; [lia |].
    apply Z.leb_gt in Hs2_start.
    apply Z.leb_gt in Hs2_end.
    assert ((s2 - start_s) * 1000 >= 0) by nia.
    assert (0 <= ((s2 - start_s) * 1000) / (end_s - start_s)) by (apply Z.div_pos; lia).
    lia.
  - apply Z.leb_gt in Hs1_start.
    assert (Hs2_start: s2 <=? start_s = false) by (apply Z.leb_gt; lia).
    rewrite Hs2_start.
    destruct (end_s <=? s1) eqn:Hs1_end.
    + apply Z.leb_le in Hs1_end.
      assert (Hs2_end: end_s <=? s2 = true) by (apply Z.leb_le; lia).
      rewrite Hs2_end.
      lia.
    + apply Z.leb_gt in Hs1_end.
      destruct (end_s <=? s2) eqn:Hs2_end.
      * apply Z.div_le_upper_bound; [lia | nia].
      * apply Z.leb_gt in Hs2_end.
        apply Z.div_le_mono; [lia |].
        nia.
Qed.
