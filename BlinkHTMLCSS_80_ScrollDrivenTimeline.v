(* Blink2Coq HTML/CSS Synthesis for ScrollDrivenTimeline *)
(* Source: renderer/core/animation/scroll_timeline.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition scroll_progress_pct (offset start_off end_off : Z) : Z :=
  let range := end_off - start_off in
  if range <=? 0 then 0
  else if offset <=? start_off then 0
  else if end_off <=? offset then 100
  else ((offset - start_off) * 100) / range.
Theorem scroll_progress_bounded : forall off s e,
  0 <= scroll_progress_pct off s e <= 100.
Proof.
  intros off s e. unfold scroll_progress_pct.
  destruct (e - s <=? 0) eqn:Er; [lia |].
  apply Z.leb_gt in Er.
  destruct (off <=? s) eqn:Es; [lia |].
  apply Z.leb_gt in Es.
  destruct (e <=? off) eqn:Ee; [lia |].
  apply Z.leb_gt in Ee.
  split.
  - apply Z.div_pos; [lia | lia].
  - apply Z.div_le_upper_bound; [lia |].
    assert (off - s < e - s) by lia.
    assert ((off - s) * 100 <= (e - s) * 100) by lia.
    exact H0.
Qed.
